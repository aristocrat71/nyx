use crate::engine::{self, State};
use tauri::image::Image;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager, Wry};

const IDLE: &[u8] = include_bytes!("../assets/tray/tray-idle.png");
const ACTIVE_LIGHT: &[u8] = include_bytes!("../assets/tray/tray-active-light.png");
const ACTIVE_DARK: &[u8] = include_bytes!("../assets/tray/tray-active-dark.png");
const BLIND_LIGHT: &[u8] = include_bytes!("../assets/tray/tray-blind-light.png");
const BLIND_DARK: &[u8] = include_bytes!("../assets/tray/tray-blind-dark.png");

struct Items {
    protection: CheckMenuItem<Wry>,
}

pub fn build(app: &AppHandle) -> tauri::Result<()> {
    let protection = CheckMenuItem::with_id(app, "protection", "Protection: On", true, true, None::<&str>)?;
    let dashboard = MenuItem::with_id(app, "dashboard", "Open Dashboard", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Nyx", true, Some("CmdOrCtrl+Q"))?;
    let separator = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(app, &[&protection, &dashboard, &separator, &quit])?;
    TrayIconBuilder::with_id("nyx")
        .icon(Image::from_bytes(IDLE)?)
        .icon_as_template(true)
        .tooltip("Nyx")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "protection" => {
                engine::with(|nyx| nyx.set_enabled(!nyx.list.enabled));
            }
            "dashboard" => crate::show_dashboard(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    app.manage(Items { protection });
    Ok(())
}

/// Idle is a template outline; engaged icons carry a dot, amber mirroring, red hidden with no preview.
pub fn set_state(app: &AppHandle, state: State) {
    let Some(tray) = app.tray_by_id("nyx") else { return };
    let dark = crate::platform::dark_menu_bar();
    let (bytes, tip) = match state {
        State::Idle => (IDLE, "Nyx — idle"),
        State::Active => (if dark { ACTIVE_DARK } else { ACTIVE_LIGHT }, "Nyx — protecting this window"),
        State::Blind => (if dark { BLIND_DARK } else { BLIND_LIGHT }, "Nyx — window hidden, no local preview"),
    };
    let _ = tray.set_icon(Image::from_bytes(bytes).ok());
    let _ = tray.set_icon_as_template(state == State::Idle);
    let _ = tray.set_tooltip(Some(tip));
}

pub fn refresh(app: &AppHandle, enabled: bool) {
    let items = app.state::<Items>();
    let _ = items.protection.set_checked(enabled);
    let _ = items.protection.set_text(if enabled { "Protection: On" } else { "Protection: Off" });
}
