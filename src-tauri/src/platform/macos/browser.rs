use objc2_application_services::{AXError, AXIsProcessTrusted, AXIsProcessTrustedWithOptions, AXUIElement};
use objc2_core_foundation::{kCFBooleanTrue, CFArray, CFDictionary, CFRetained, CFString, CFType, CFURL};
use objc2_foundation::{NSString, NSURL};
use std::collections::VecDeque;
use std::ptr::NonNull;
use std::sync::atomic::{AtomicI32, Ordering};

// Browsers: site rules only ever apply to one, and only while it is frontmost.

const BROWSERS: &[&str] = &[
    "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
    "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox",
    "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "company.thebrowser.Browser",
    "company.thebrowser.dia", "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
    "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.operasoftware.Opera",
    "com.operasoftware.OperaGX", "com.vivaldi.Vivaldi", "app.zen-browser.zen", "com.kagi.kagimacOS",
];

pub fn is_browser(id: &str) -> bool {
    BROWSERS.contains(&id)
}

/// Either field can be absent: Firefox exposes no URL, only a window title.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Tab {
    pub host: Option<String>,
    pub title: Option<String>,
}

pub fn has_accessibility_permission() -> bool {
    unsafe { AXIsProcessTrusted() }
}

/// Asks once with the system prompt, then opens the pane in case the prompt was dismissed before.
pub fn open_accessibility_settings() {
    let key = CFString::from_str("AXTrustedCheckOptionPrompt");
    let yes = unsafe { kCFBooleanTrue }.expect("CFBoolean true exists");
    let options = CFDictionary::from_slices(&[&*key], &[yes]);
    unsafe { AXIsProcessTrustedWithOptions(Some(options.as_opaque())) };
    super::open_url("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility");
}

/// Reads are given far less than the 6 s default, so a hung browser never stalls the main thread.
const AX_TIMEOUT: f32 = 0.2;
const AX_MAX_DEPTH: usize = 8;
const AX_MAX_CHILDREN: usize = 40;
const AX_MAX_NODES: usize = 300;

pub fn browser_tab(pid: i32) -> Option<Tab> {
    if !has_accessibility_permission() {
        return None;
    }
    let app = unsafe { AXUIElement::new_application(pid) };
    unsafe { app.set_messaging_timeout(AX_TIMEOUT) };
    enable_web_tree(pid, &app);
    let window = ax(&app, "AXFocusedWindow")?.downcast::<AXUIElement>().ok()?;
    let title = ax(&window, "AXTitle").and_then(|t| t.downcast_ref::<CFString>().map(|t| t.to_string()));
    // Safari puts the front tab's address on the window, which saves walking the tree.
    let document = ax(&window, "AXDocument").and_then(|d| d.downcast_ref::<CFString>().map(|d| d.to_string()));
    let host = document.and_then(|d| host_of(&d)).or_else(|| web_area_host(window));
    (host.is_some() || title.is_some()).then_some(Tab { host, title })
}

/// Chrome-family browsers keep the web tree out of AX until something asks; asked once per browser.
fn enable_web_tree(pid: i32, app: &AXUIElement) {
    static ENABLED: AtomicI32 = AtomicI32::new(0);
    if ENABLED.swap(pid, Ordering::Relaxed) != pid {
        let yes = unsafe { kCFBooleanTrue }.expect("CFBoolean true exists");
        unsafe { app.set_attribute_value(&CFString::from_str("AXManualAccessibility"), yes) };
    }
}

fn ax(element: &AXUIElement, attribute: &str) -> Option<CFRetained<CFType>> {
    let mut value: *const CFType = std::ptr::null();
    let status = unsafe { element.copy_attribute_value(&CFString::from_str(attribute), NonNull::from(&mut value)) };
    (status == AXError::Success).then(|| NonNull::new(value as *mut CFType)).flatten().map(|v| unsafe { CFRetained::from_raw(v) })
}

fn web_area_host(root: CFRetained<AXUIElement>) -> Option<String> {
    let mut queue = VecDeque::from([(root, 0)]);
    let mut visited = 0;
    while let Some((node, depth)) = queue.pop_front().filter(|_| visited < AX_MAX_NODES) {
        visited += 1;
        let role = ax(&node, "AXRole").and_then(|r| r.downcast_ref::<CFString>().map(|r| r.to_string()));
        if role.as_deref() == Some("AXWebArea") {
            if let Some(host) = ax(&node, "AXURL").and_then(|u| url_host(&u)) {
                return Some(host);
            }
        }
        if depth >= AX_MAX_DEPTH {
            continue;
        }
        let Some(children) = ax(&node, "AXChildren").and_then(|c| c.downcast::<CFArray>().ok()) else { continue };
        let children: &CFArray<CFType> = unsafe { &*(&*children as *const CFArray as *const CFArray<CFType>) };
        for child in children.iter().take(AX_MAX_CHILDREN) {
            if let Ok(child) = child.downcast::<AXUIElement>() {
                queue.push_back((child, depth + 1));
            }
        }
    }
    None
}

fn url_host(value: &CFType) -> Option<String> {
    if let Some(text) = value.downcast_ref::<CFString>() {
        return host_of(&text.to_string());
    }
    let url: &NSURL = unsafe { &*(value.downcast_ref::<CFURL>()? as *const CFURL as *const NSURL) };
    url.host().map(|h| h.to_string())
}

fn host_of(text: &str) -> Option<String> {
    NSURL::URLWithString(&NSString::from_str(text))?.host().map(|h| h.to_string())
}
