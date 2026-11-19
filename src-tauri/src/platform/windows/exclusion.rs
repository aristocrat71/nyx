use std::sync::Once;
use windows::Win32::Foundation::HWND;
use windows::Win32::UI::Accessibility::{SetWinEventHook, HWINEVENTHOOK};
use windows::Win32::UI::WindowsAndMessaging::{
    SetWindowDisplayAffinity, EVENT_SYSTEM_MENUPOPUPSTART, WDA_EXCLUDEFROMCAPTURE, WINEVENT_OUTOFCONTEXT,
};

// Viewers must never see Nyx's own UI: the list of protected apps is itself private.

pub fn exclude_window(window: &tauri::WebviewWindow) {
    if let Ok(hwnd) = window.hwnd() {
        let _ = unsafe { SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) };
    }
}

/// The tray menu is a popup window Nyx itself owns, excluded the moment Windows announces it.
/// May let one frame through before the event lands; verify on a real share.
pub fn exclude_tray_menu(_tray: &tauri::tray::TrayIcon) {
    static HOOK: Once = Once::new();
    HOOK.call_once(|| unsafe {
        let event = EVENT_SYSTEM_MENUPOPUPSTART;
        SetWinEventHook(event, event, None, Some(menu_shown), std::process::id(), 0, WINEVENT_OUTOFCONTEXT);
    });
}

unsafe extern "system" fn menu_shown(_: HWINEVENTHOOK, _: u32, hwnd: HWND, _: i32, _: i32, _: u32, _: u32) {
    let _ = unsafe { SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE) };
}
