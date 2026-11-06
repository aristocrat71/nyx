mod apps;
mod browser;
mod exclusion;
#[path = "../exe_identity.rs"]
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
use windows::core::{w, HSTRING, PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, HWND};
use windows::Win32::System::Registry::{
    RegCloseKey, RegEnumKeyExW, RegGetValueW, RegNotifyChangeKeyValue, RegOpenKeyExW, HKEY, HKEY_CURRENT_USER, KEY_NOTIFY,
    KEY_READ, REG_NOTIFY_CHANGE_LAST_SET, REG_NOTIFY_CHANGE_NAME, RRF_RT_REG_DWORD, RRF_RT_REG_QWORD,
};
use windows::Win32::System::Threading::{
    CreateEventW, OpenProcess, QueryFullProcessImageNameW, WaitForSingleObject, INFINITE, PROCESS_NAME_WIN32,
    PROCESS_QUERY_LIMITED_INFORMATION,
};
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

// Capture gate: Windows records each app's screen-capture use in the same consent store
// that drives the mic and camera indicators. Undocumented; verified per capturer by hand.

const CONSENT: &str = r"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore";
const CAPABILITIES: [&str; 2] = ["graphicsCaptureProgrammatic", "graphicsCaptureWithoutBorder"];

struct Key(HKEY);

impl Drop for Key {
    fn drop(&mut self) {
        let _ = unsafe { RegCloseKey(self.0) };
    }
}

impl Key {
    fn open(parent: HKEY, path: &str) -> Option<Key> {
        let mut key = HKEY::default();
        let status = unsafe { RegOpenKeyExW(parent, &HSTRING::from(path), None, KEY_READ | KEY_NOTIFY, &mut key) };
        status.is_ok().then_some(Key(key))
    }

    fn children(&self) -> Vec<(String, Key)> {
        let mut found = Vec::new();
        for index in 0.. {
            let mut name = [0u16; 512];
            let mut len = name.len() as u32;
            let status = unsafe { RegEnumKeyExW(self.0, index, Some(PWSTR(name.as_mut_ptr())), &mut len, None, None, None, None) };
            if status.is_err() {
                break;
            }
            let name = String::from_utf16_lossy(&name[..len as usize]);
            found.extend(Key::open(self.0, &name).map(|key| (name, key)));
        }
        found
    }

    fn number(&self, value: PCWSTR, kind: windows::Win32::System::Registry::REG_ROUTINE_FLAGS) -> Option<u64> {
        let mut data = 0u64;
        let mut size = 8u32;
        let status = unsafe { RegGetValueW(self.0, None, value, kind, None, Some(&mut data as *mut u64 as _), Some(&mut size)) };
        status.is_ok().then_some(data)
    }

    /// Started and not yet stopped: the app holds the capability right now.
    fn in_use(&self) -> bool {
        let start = self.number(w!("LastUsedTimeStart"), RRF_RT_REG_QWORD).unwrap_or(0);
        let stop = self.number(w!("LastUsedTimeStop"), RRF_RT_REG_QWORD).unwrap_or(1);
        start != 0 && stop == 0
    }
}

/// Fails closed when the store is missing. Nyx's own mirror registers too, under its own path, so it is skipped.
pub fn capturing() -> bool {
    let me = std::env::current_exe().map(|p| p.to_string_lossy().replace('\\', "#").to_lowercase()).unwrap_or_default();
    let mut store_found = false;
    for capability in CAPABILITIES {
        let Some(root) = Key::open(HKEY_CURRENT_USER, &format!(r"{CONSENT}\{capability}")) else { continue };
        store_found = true;
        for (name, key) in root.children() {
            let busy = if name == "NonPackaged" {
                key.children().iter().any(|(exe, k)| exe.to_lowercase() != me && k.in_use())
            } else {
                key.in_use()
            };
            if busy {
                return true;
            }
        }
    }
    !store_found
}

pub fn observe_capture(changed: fn()) {
    std::thread::spawn(move || {
        let (Some(store), Ok(event)) = (Key::open(HKEY_CURRENT_USER, CONSENT), unsafe { CreateEventW(None, false, false, None) }) else {
            return log::error!("cannot watch the capture consent store, relying on the poll");
        };
        loop {
            let filter = REG_NOTIFY_CHANGE_LAST_SET | REG_NOTIFY_CHANGE_NAME;
            if unsafe { RegNotifyChangeKeyValue(store.0, true, filter, Some(event), true) }.is_err() {
                return;
            }
            unsafe { WaitForSingleObject(event, INFINITE) };
            changed();
        }
    });
}

/// The taskbar follows the system theme, which the dashboard's own setting never touches.
pub fn dark_menu_bar() -> bool {
    Key::open(HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
        .and_then(|k| k.number(w!("SystemUsesLightTheme"), RRF_RT_REG_DWORD))
        .is_some_and(|light| light & 0xffff_ffff == 0)
}

/// Windows asks no permission to capture or read other windows.
pub fn has_screen_permission() -> bool {
    true
}

/// A limit of this platform the dashboard should state plainly; none here.
pub fn notice() -> Option<&'static str> {
    None
}

pub fn request_screen_permission() {}

pub fn open_screen_settings() {}

pub fn open_url(url: &str) {
    unsafe { ShellExecuteW(None, w!("open"), &HSTRING::from(url), None, None, SW_SHOWNORMAL) };
}
