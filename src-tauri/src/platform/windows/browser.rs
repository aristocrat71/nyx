use super::window_pid;
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowTextW};

const BROWSERS: &[&str] = &[
    "chrome.exe", "msedge.exe", "firefox.exe", "brave.exe", "opera.exe", "vivaldi.exe", "arc.exe", "zen.exe",
    "chromium.exe", "librewolf.exe", "waterfox.exe",
];

pub fn is_browser(id: &str) -> bool {
    BROWSERS.contains(&id)
}

/// Either field can be absent; on Windows only the title is read for now.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Tab {
    pub host: Option<String>,
    pub title: Option<String>,
}

/// ponytail: title only, matched on the brand label like Firefox on macOS. Upgrade: read the address
/// bar through UI Automation's ValuePattern to match hosts exactly.
pub fn browser_tab(pid: i32) -> Option<Tab> {
    let hwnd = unsafe { GetForegroundWindow() };
    if window_pid(hwnd) != pid as u32 {
        return None;
    }
    let mut text = [0u16; 512];
    let len = unsafe { GetWindowTextW(hwnd, &mut text) } as usize;
    (len > 0).then(|| Tab { host: None, title: Some(String::from_utf16_lossy(&text[..len])) })
}

/// Reading another app's window title needs no permission on Windows.
pub fn has_accessibility_permission() -> bool {
    true
}

pub fn open_accessibility_settings() {}
