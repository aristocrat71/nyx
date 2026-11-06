#[path = "../exe_identity.rs"]
mod identity;
mod overlay;

pub use identity::{check_identity, designated_requirement};
pub use overlay::{windows_of, Placeholders};

use crate::store::ProtectedApp;
use std::path::{Path, PathBuf};

// Linux: X11 only. No X11 API can keep a window out of a capture, so Nyx covers protected apps
// for the user too, and it cannot tell a share apart from no share, so it always covers.

#[derive(Clone)]
pub struct App {
    pub pid: i32,
    pub id: String,
    pub name: String,
    pub path: Option<PathBuf>,
}

pub fn frontmost() -> Option<App> {
    None
}

pub fn protectable() -> Option<App> {
    frontmost()
}

pub fn observe(_app_changed: fn(), _screens_changed: fn()) {}

pub fn observe_capture(_changed: fn()) {}

/// Fails closed: X11 has no capture signal, so every protected app is treated as watched.
pub fn capturing() -> bool {
    true
}

pub fn notice() -> Option<&'static str> {
    Some("Linux cannot hide a window from a capture or tell when one runs, so protected apps are covered for you too, whenever they are in front.")
}

pub fn dark_menu_bar() -> bool {
    false
}

pub fn has_screen_permission() -> bool {
    true
}

pub fn request_screen_permission() {}

pub fn open_screen_settings() {}

pub fn open_url(url: &str) {
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

/// No mirror: nothing on Linux keeps one out of the capture, so the user sees the cover too.
#[derive(Default)]
pub struct Mirror;

impl Mirror {
    pub fn start(&mut self, _pid: i32) {}
    pub fn stop(&mut self) {}
    pub fn restack(&mut self, _targets: &[overlay::Target]) {}
}

pub fn exclude_window(_window: &tauri::WebviewWindow) {}

pub fn exclude_tray_menu(_tray: &tauri::tray::TrayIcon) {}

pub fn is_browser(_id: &str) -> bool {
    false
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Tab {
    pub host: Option<String>,
    pub title: Option<String>,
}

pub fn browser_tab(_pid: i32) -> Option<Tab> {
    None
}

pub fn has_accessibility_permission() -> bool {
    true
}

pub fn open_accessibility_settings() {}

pub struct Installed {
    pub id: String,
    pub name: String,
    pub path: PathBuf,
}

pub fn pickable() -> Vec<Installed> {
    vec![]
}

pub fn app_at(_path: &Path) -> Option<Installed> {
    None
}

pub fn icon_png(_path: &Path) -> Option<Vec<u8>> {
    None
}

pub fn protected_icon(_app: &ProtectedApp) -> Option<Vec<u8>> {
    None
}
