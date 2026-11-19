use block2::RcBlock;
use objc2_app_kit::{
    NSApplicationDidChangeScreenParametersNotification, NSRunningApplication, NSWorkspace,
    NSWorkspaceDidActivateApplicationNotification, NSWorkspaceDidTerminateApplicationNotification,
};
use objc2_core_graphics::CGPreflightScreenCaptureAccess;
use objc2_foundation::{NSNotificationCenter, NSOperationQueue, NSString, NSURL, NSUserDefaults};
use std::ffi::{c_char, c_void, CStr};
use std::path::PathBuf;
use std::sync::OnceLock;

mod apps;
mod browser;
mod exclusion;
mod identity;
mod mirror;
mod overlay;

pub use apps::{app_at, icon_png, pickable, protected_path};
pub use browser::{browser_tab, has_accessibility_permission, is_browser, open_accessibility_settings, Tab};
pub use exclusion::{exclude_tray_menu, exclude_window};
pub use identity::{check_identity, designated_requirement};
pub use mirror::Mirror;
pub use overlay::{windows_of, Placeholders};

#[derive(Clone)]
pub struct App {
    pub pid: i32,
    pub id: String,
    pub name: String,
    pub path: Option<PathBuf>,
}

pub fn frontmost() -> Option<App> {
    let app = NSWorkspace::sharedWorkspace().frontmostApplication()?;
    let pid = app.processIdentifier();
    if pid == NSRunningApplication::currentApplication().processIdentifier() {
        return None;
    }
    let id = app.bundleIdentifier()?.to_string();
    let name = app.localizedName().map_or_else(|| id.clone(), |n| n.to_string());
    let path = app.bundleURL().and_then(|u| u.to_file_path());
    Some(App { pid, id, name, path })
}

/// What the tray item and the hotkey act on. Finder is out because it owns the desktop.
pub fn protectable() -> Option<App> {
    frontmost().filter(|app| app.id != "com.apple.finder")
}

/// `app_changed` on every app switch or quit, `screens_changed` when displays change.
pub fn observe(app_changed: fn(), screens_changed: fn()) {
    let queue = NSOperationQueue::mainQueue();
    let workspace = NSWorkspace::sharedWorkspace().notificationCenter();
    let app_block = RcBlock::new(move |_| app_changed());
    let screens_block = RcBlock::new(move |_| screens_changed());
    // The observers live as long as the process, so their tokens are never removed.
    unsafe {
        for name in [NSWorkspaceDidActivateApplicationNotification, NSWorkspaceDidTerminateApplicationNotification] {
            std::mem::forget(workspace.addObserverForName_object_queue_usingBlock(Some(name), None, Some(&queue), &app_block));
        }
        let name = NSApplicationDidChangeScreenParametersNotification;
        let center = NSNotificationCenter::defaultCenter();
        std::mem::forget(center.addObserverForName_object_queue_usingBlock(Some(name), None, Some(&queue), &screens_block));
    }
}

// Capture gate: WindowServer's screen-watcher flag, resolved by name so the private
// framework is never linked. Needs no permission, but counts Nyx's own mirror too.

type NotifyProc = extern "C" fn(u32, *mut c_void, u32, *mut c_void);
struct SkyLight {
    is_watched: extern "C" fn() -> bool,
    register: extern "C" fn(NotifyProc, u32, *mut c_void) -> i32,
}

unsafe extern "C" {
    fn dlopen(path: *const c_char, mode: i32) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
}

fn skylight() -> Option<&'static SkyLight> {
    static SKYLIGHT: OnceLock<Option<SkyLight>> = OnceLock::new();
    SKYLIGHT
        .get_or_init(|| unsafe {
            let path = c"/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight";
            let handle = dlopen(path.as_ptr(), 1);
            let sym = |name: &CStr| (!handle.is_null()).then(|| dlsym(handle, name.as_ptr())).filter(|p| !p.is_null());
            Some(SkyLight {
                is_watched: std::mem::transmute(sym(c"SLSIsScreenWatcherPresent")?),
                register: std::mem::transmute(sym(c"SLSRegisterNotifyProc")?),
            })
        })
        .as_ref()
}

static ON_CAPTURE: OnceLock<fn()> = OnceLock::new();

extern "C" fn capture_notified(_: u32, _: *mut c_void, _: u32, _: *mut c_void) {
    if let Some(changed) = ON_CAPTURE.get() {
        changed();
    }
}

/// WindowServer's capture-started/stopped notifications; `capturing()` is still polled
/// because whether they fire for a second capturer is unverified.
pub fn observe_capture(changed: fn()) {
    let Some(sl) = skylight() else { return };
    let _ = ON_CAPTURE.set(changed);
    for kind in [1502, 1503] {
        let status = (sl.register)(capture_notified, kind, std::ptr::null_mut());
        if status != 0 {
            log::error!("registering capture notification {kind} failed: {status}");
        }
    }
}

/// Fails closed: without the flag every protected app is covered, which never leaks.
pub fn capturing() -> bool {
    skylight().is_none_or(|sl| (sl.is_watched)())
}

/// The menu bar follows the system appearance, which the dashboard's own setting never touches.
pub fn dark_menu_bar() -> bool {
    let style = NSUserDefaults::standardUserDefaults().stringForKey(&NSString::from_str("AppleInterfaceStyle"));
    style.is_some_and(|s| s.to_string() == "Dark")
}

pub fn has_screen_permission() -> bool {
    CGPreflightScreenCaptureAccess()
}

/// A limit of this platform the dashboard should state plainly; none here.
pub fn notice() -> Option<&'static str> {
    None
}

pub fn open_screen_settings() {
    open_url("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture");
}

pub fn open_url(url: &str) {
    if let Some(url) = NSURL::URLWithString(&NSString::from_str(url)) {
        NSWorkspace::sharedWorkspace().openURL(&url);
    }
}
