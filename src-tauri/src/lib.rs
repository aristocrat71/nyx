mod engine;
mod site;
mod store;
mod tray;

#[cfg(target_os = "macos")]
#[path = "platform/macos/mod.rs"]
mod platform;

use engine::State;
use tauri::{AppHandle, Manager, WindowEvent};

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

fn list_changed(list: &store::ProtectionList) {
    tray::refresh(engine::app(), list.enabled);
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

    tauri::Builder::default()
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            let path = app.path().config_dir()?.join("Nyx/protected.json");
            tray::build(app.handle())?;
            engine::start(app.handle().clone(), store::ProtectionList::load(path));
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
