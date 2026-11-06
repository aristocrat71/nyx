#[path = "../exe_identity.rs"]
mod identity;
mod overlay;

pub use identity::{check_identity, designated_requirement};
pub use overlay::{windows_of, Placeholders};

use crate::store::ProtectedApp;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use x11rb::connection::Connection;
use x11rb::protocol::xproto::{Atom, AtomEnum, ChangeWindowAttributesAux, ConnectionExt, EventMask, Window};
use x11rb::protocol::Event;
use x11rb::rust_connection::RustConnection;

// Linux: X11 only. No X11 API can keep a window out of a capture, so Nyx covers protected apps
// for the user too, and it cannot tell a share apart from no share, so it always covers.

pub(super) struct X {
    pub conn: RustConnection,
    pub root: Window,
    pub depth: u8,
    active: Atom,
    pid: Atom,
    clients: Atom,
    name: Atom,
    utf8: Atom,
}

fn wayland() -> bool {
    std::env::var("XDG_SESSION_TYPE").is_ok_and(|s| s == "wayland")
}

/// None in a Wayland session: XWayland only sees X clients, so covering would be wrong both ways.
pub(super) fn x() -> Option<&'static X> {
    static X11: OnceLock<Option<X>> = OnceLock::new();
    X11.get_or_init(|| {
        if wayland() {
            return None;
        }
        let (conn, screen) = x11rb::connect(None).ok()?;
        let (root, depth) = (conn.setup().roots[screen].root, conn.setup().roots[screen].root_depth);
        let atom = |name: &str| conn.intern_atom(false, name.as_bytes()).ok()?.reply().ok().map(|r| r.atom);
        Some(X {
            active: atom("_NET_ACTIVE_WINDOW")?,
            pid: atom("_NET_WM_PID")?,
            clients: atom("_NET_CLIENT_LIST")?,
            name: atom("_NET_WM_NAME")?,
            utf8: atom("UTF8_STRING")?,
            conn,
            root,
            depth,
        })
    })
    .as_ref()
}

impl X {
    fn words(&self, window: Window, property: Atom, count: u32) -> Vec<u32> {
        let reply = self.conn.get_property(false, window, property, AtomEnum::ANY, 0, count).ok().and_then(|c| c.reply().ok());
        reply.and_then(|r| r.value32().map(|v| v.collect())).unwrap_or_default()
    }

    pub(super) fn pid_of(&self, window: Window) -> Option<u32> {
        self.words(window, self.pid, 1).first().copied()
    }

    fn title(&self, window: Window) -> Option<String> {
        let reply = self.conn.get_property(false, window, self.name, self.utf8, 0, 1024).ok()?.reply().ok()?;
        (!reply.value.is_empty()).then(|| String::from_utf8_lossy(&reply.value).into_owned())
    }
}

#[derive(Clone)]
pub struct App {
    pub pid: i32,
    pub id: String,
    pub name: String,
    pub path: Option<PathBuf>,
}

fn app_for_pid(pid: u32) -> Option<App> {
    let path = std::fs::read_link(format!("/proc/{pid}/exe")).ok()?;
    let id = path.file_name()?.to_string_lossy().to_lowercase();
    let name = path.file_stem()?.to_string_lossy().into_owned();
    Some(App { pid: pid as i32, id, name, path: Some(path) })
}

pub fn frontmost() -> Option<App> {
    let x = x()?;
    let window = *x.words(x.root, x.active, 1).first()?;
    let pid = x.pid_of(window).filter(|p| *p != std::process::id())?;
    app_for_pid(pid)
}

pub fn protectable() -> Option<App> {
    frontmost()
}

/// The window manager announces every focus change on the root window's active-window property.
pub fn observe(app_changed: fn(), _screens_changed: fn()) {
    let Some(x) = x() else { return };
    let active = x.active;
    std::thread::spawn(move || {
        let Ok((conn, screen)) = x11rb::connect(None) else { return };
        let root = conn.setup().roots[screen].root;
        let mask = ChangeWindowAttributesAux::new().event_mask(EventMask::PROPERTY_CHANGE);
        if conn.change_window_attributes(root, &mask).is_err() || conn.flush().is_err() {
            return;
        }
        while let Ok(event) = conn.wait_for_event() {
            if matches!(event, Event::PropertyNotify(e) if e.atom == active) {
                app_changed();
            }
        }
    });
}

pub fn observe_capture(_changed: fn()) {}

/// Fails closed: X11 has no capture signal, so every protected app is treated as watched.
pub fn capturing() -> bool {
    true
}

pub fn notice() -> Option<&'static str> {
    Some(if x().is_some() {
        "Linux cannot hide a window from a capture or tell when one runs, so protected apps are covered for you too, whenever they are in front."
    } else {
        "Nyx cannot see or cover other windows in a Wayland session. Log in with an X11 session to use it."
    })
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
