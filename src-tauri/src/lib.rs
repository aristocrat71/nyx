mod commands;
mod engine;
mod site;
mod store;
mod tray;

#[cfg(target_os = "macos")]
#[path = "platform/macos/mod.rs"]
mod platform;
#[cfg(target_os = "windows")]
#[path = "platform/windows/mod.rs"]
mod platform;
#[cfg(target_os = "linux")]
#[path = "platform/linux/mod.rs"]
mod platform;

use engine::State;
use tauri::{AppHandle, Emitter, Manager, WindowEvent};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

struct StderrLog;

impl log::Log for StderrLog {
    fn enabled(&self, _: &log::Metadata) -> bool {
        true
    }
    fn log(&self, record: &log::Record) {
        eprintln!("nyx: {} {}", record.level(), record.args());
    }
    fn flush(&self) {}
}

fn state_changed(state: State) {
    log::debug!("state {state:?}");
    tray::set_state(engine::app(), state);
}

fn changed(nyx: &engine::Nyx) {
    tray::refresh(engine::app(), nyx);
    let _ = engine::app().emit("changed", ());
}

fn show_dashboard(app: &AppHandle) {
    if let Some(dashboard) = app.get_webview_window("dashboard") {
        let _ = dashboard.show();
        let _ = dashboard.set_focus();
    }
}

#[cfg_attr(target_os = "linux", allow(dead_code))]
fn permission_lost() {
    log::error!("screen recording permission lost");
}

pub fn run() {
    let _ = log::set_logger(&StderrLog);
    // Routine activity says which app is open and when, so release builds keep errors only.
    log::set_max_level(if cfg!(debug_assertions) { log::LevelFilter::Debug } else { log::LevelFilter::Error });

    let hotkey = tauri_plugin_global_shortcut::Builder::new().with_handler(|_, _, event| {
        if event.state == ShortcutState::Pressed {
            engine::post(engine::Nyx::toggle_front);
        }
    });

    tauri::Builder::default()
        .plugin(hotkey.build())
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .register_asynchronous_uri_scheme_protocol("icon", |_, request, responder| commands::icon(request, responder))
        .invoke_handler(tauri::generate_handler![
            commands::snapshot,
            commands::pickable,
            commands::add_app,
            commands::remove_app,
            commands::add_site,
            commands::normalize_site,
            commands::remove_site,
            commands::open_link,
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            platform::request_screen_permission();
            let path = app.path().config_dir()?.join("Nyx/protected.json");
            if let Some(dashboard) = app.get_webview_window("dashboard") {
                platform::exclude_window(&dashboard);
            }
            tray::build(app.handle())?;
            let list = store::ProtectionList::load(path);
            let shortcut = list.hotkey.shortcut().or(store::HotkeySpec::STANDARD.shortcut());
            if let Err(e) = shortcut.map(|s| app.global_shortcut().register(s)).transpose() {
                log::error!("hotkey registration failed: {e}");
            }
            // Otherwise Nyx starts quietly in the tray: the dashboard opens only when it needs the user.
            let needs_user = !platform::has_screen_permission() || list.load_failed || list.apps.is_empty();
            engine::start(app.handle().clone(), list);
            if needs_user {
                show_dashboard(app.handle());
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running Nyx");
}
