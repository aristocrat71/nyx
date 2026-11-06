mod engine;
mod site;
mod store;
mod tray;

#[cfg(target_os = "macos")]
#[path = "platform/macos/mod.rs"]
mod platform;

use engine::State;
use tauri::{AppHandle, Manager, WindowEvent};
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
}

fn show_dashboard(app: &AppHandle) {
    if let Some(dashboard) = app.get_webview_window("dashboard") {
        let _ = dashboard.show();
        let _ = dashboard.set_focus();
    }
}

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
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            let path = app.path().config_dir()?.join("Nyx/protected.json");
            tray::build(app.handle())?;
            let list = store::ProtectionList::load(path);
            let shortcut = list.hotkey.shortcut().or(store::HotkeySpec::STANDARD.shortcut());
            if let Err(e) = shortcut.map(|s| app.global_shortcut().register(s)).transpose() {
                log::error!("hotkey registration failed: {e}");
            }
            engine::start(app.handle().clone(), list);
            show_dashboard(app.handle());
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
