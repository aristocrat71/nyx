mod apps;
mod browser;
mod exclusion;
mod identity;
mod mirror;
mod overlay;

pub use apps::{app_at, icon_png, pickable, protected_icon};
pub use browser::{browser_tab, has_accessibility_permission, is_browser, open_accessibility_settings, Tab};
pub use exclusion::{exclude_tray_menu, exclude_window};
pub use identity::{check_identity, designated_requirement};
pub use mirror::Mirror;
pub use overlay::{windows_of, Placeholders};

use std::path::PathBuf;
use std::sync::OnceLock;
use windows::core::{w, HSTRING, PWSTR};
use windows::Win32::Foundation::{CloseHandle, HWND};
use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
use windows::Win32::UI::Accessibility::{SetWinEventHook, HWINEVENTHOOK};
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::{
    GetForegroundWindow, GetWindowThreadProcessId, EVENT_SYSTEM_FOREGROUND, SW_SHOWNORMAL, WINEVENT_OUTOFCONTEXT,
    WINEVENT_SKIPOWNPROCESS,
};

/// `id` is the lowercase executable name: Windows has no bundle id, and the exe is what the user picked.
#[derive(Clone)]
pub struct App {
    pub pid: i32,
    pub id: String,
    pub name: String,
    pub path: Option<PathBuf>,
}

fn process_path(pid: u32) -> Option<PathBuf> {
    unsafe {
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = [0u16; 1024];
        let mut len = buf.len() as u32;
        let read = QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
        let _ = CloseHandle(process);
        read.ok().map(|_| PathBuf::from(String::from_utf16_lossy(&buf[..len as usize])))
    }
}

fn app_for_pid(pid: u32) -> Option<App> {
    let path = process_path(pid)?;
    let id = path.file_name()?.to_string_lossy().to_lowercase();
    let name = path.file_stem()?.to_string_lossy().into_owned();
    Some(App { pid: pid as i32, id, name, path: Some(path) })
}

fn window_pid(hwnd: HWND) -> u32 {
    let mut pid = 0;
    unsafe { GetWindowThreadProcessId(hwnd, Some(&mut pid)) };
    pid
}

pub fn frontmost() -> Option<App> {
    let pid = window_pid(unsafe { GetForegroundWindow() });
    (pid != 0 && pid != std::process::id()).then(|| app_for_pid(pid)).flatten()
}

/// What the tray item and the hotkey act on. Explorer is out because it owns the desktop and taskbar.
pub fn protectable() -> Option<App> {
    frontmost().filter(|app| app.id != "explorer.exe")
}

static APP_CHANGED: OnceLock<fn()> = OnceLock::new();

unsafe extern "system" fn foreground_changed(_: HWINEVENTHOOK, _: u32, _: HWND, _: i32, _: i32, _: u32, _: u32) {
    if let Some(changed) = APP_CHANGED.get() {
        changed();
    }
}

/// Mirrors follow windows, not displays, so a display change needs no rebuild here.
pub fn observe(app_changed: fn(), _screens_changed: fn()) {
    let _ = APP_CHANGED.set(app_changed);
    let flags = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS;
    unsafe { SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, None, Some(foreground_changed), 0, 0, flags) };
}

/// Fails closed until the consent-store gate lands: every protected app is covered.
pub fn capturing() -> bool {
    true
}

pub fn observe_capture(_changed: fn()) {}

pub fn dark_menu_bar() -> bool {
    false
}

/// Windows asks no permission to capture or read other windows.
pub fn has_screen_permission() -> bool {
    true
}

pub fn request_screen_permission() {}

pub fn open_screen_settings() {}

pub fn open_url(url: &str) {
    unsafe { ShellExecuteW(None, w!("open"), &HSTRING::from(url), None, None, SW_SHOWNORMAL) };
}
