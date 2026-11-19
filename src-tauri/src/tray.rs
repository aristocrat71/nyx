use crate::engine::{self, Nyx, State};
use tauri::image::Image;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Manager, Wry};
use tauri_plugin_autostart::ManagerExt;

const IDLE: &[u8] = include_bytes!("../assets/tray/tray-idle.png");
const ACTIVE_LIGHT: &[u8] = include_bytes!("../assets/tray/tray-active-light.png");
const ACTIVE_DARK: &[u8] = include_bytes!("../assets/tray/tray-active-dark.png");
const BLIND_LIGHT: &[u8] = include_bytes!("../assets/tray/tray-blind-light.png");
const BLIND_DARK: &[u8] = include_bytes!("../assets/tray/tray-blind-dark.png");

struct Items {
    protect_app: CheckMenuItem<Wry>,
    protection: CheckMenuItem<Wry>,
    login: CheckMenuItem<Wry>,
}

pub fn build(app: &AppHandle) -> tauri::Result<()> {
    let protect_app = CheckMenuItem::with_id(app, "protect-app", "Protect this app", false, false, None::<&str>)?;
    let protection = CheckMenuItem::with_id(app, "protection", "Protection: On", true, true, None::<&str>)?;
    let dashboard = MenuItem::with_id(app, "dashboard", "Open Dashboard", true, None::<&str>)?;
    let at_login = app.autolaunch().is_enabled().unwrap_or(false);
    let login = CheckMenuItem::with_id(app, "login", "Launch at Login", true, at_login, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit Nyx", true, Some("CmdOrCtrl+Q"))?;
    let (sep1, sep2) = (PredefinedMenuItem::separator(app)?, PredefinedMenuItem::separator(app)?);
    let menu = Menu::with_items(app, &[&protect_app, &sep1, &protection, &dashboard, &sep2, &login, &quit])?;
    let tray = TrayIconBuilder::with_id("nyx")
        .icon(Image::from_bytes(IDLE)?)
        .icon_as_template(true)
        .tooltip("Nyx")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "protect-app" => {
                engine::with(|nyx| nyx.toggle_front());
            }
            "protection" => {
                engine::with(|nyx| nyx.set_enabled(!nyx.list.enabled));
            }
            "dashboard" => crate::show_dashboard(app),
            "login" => toggle_launch_at_login(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;
    crate::platform::exclude_tray_menu(&tray);
    app.manage(Items { protect_app, protection, login });
    Ok(())
}

fn toggle_launch_at_login(app: &AppHandle) {
    let launcher = app.autolaunch();
    let on = launcher.is_enabled().unwrap_or(false);
    if let Err(e) = if on { launcher.disable() } else { launcher.enable() } {
        log::error!("launch at login toggle failed: {e}");
    }
    let _ = app.state::<Items>().login.set_checked(launcher.is_enabled().unwrap_or(false));
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

pub fn refresh(app: &AppHandle, nyx: &Nyx) {
    let Some(items) = app.try_state::<Items>() else { return };
    let front = nyx.front.as_ref();
    let _ = items.protect_app.set_text(front.map_or("Protect this app".into(), |a| format!("Protect {}", display_name(&a.name))));
    let _ = items.protect_app.set_enabled(front.is_some());
    let _ = items.protect_app.set_checked(front.is_some_and(|a| nyx.list.contains(&a.id)));
    let enabled = nyx.list.enabled;
    let _ = items.protection.set_checked(enabled);
    let _ = items.protection.set_text(if enabled { "Protection: On" } else { "Protection: Off" });
}

/// A menu title, so cut to one line: the name is whatever the other app's Info.plist says.
fn display_name(raw: &str) -> String {
    let line = raw.lines().next().unwrap_or("").trim();
    match line.chars().count() {
        0 => "this app".into(),
        n if n > 32 => format!("{}…", line.chars().take(32).collect::<String>().trim_end()),
        _ => line.into(),
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn display_name_is_one_short_line() {
        assert_eq!(super::display_name("Mail"), "Mail");
        assert_eq!(super::display_name("  \n"), "this app");
        assert_eq!(super::display_name("Evil\nSecond line"), "Evil");
        assert_eq!(super::display_name(&"x".repeat(40)), format!("{}…", "x".repeat(32)));
    }
}
