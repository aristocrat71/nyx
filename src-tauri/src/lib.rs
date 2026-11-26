mod commands;
mod engine;
mod site;
mod store;
mod tray;
#[cfg(target_os = "macos")]
mod update;

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
use tauri::{AppHandle, Emitter, Manager, RunEvent, WebviewWindowBuilder};
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
        return;
    }
    // Built on open and destroyed on close, so the webview costs nothing while Nyx sits in the tray.
    // Off the main thread, since building from a menu handler deadlocks on Windows.
    let app = app.clone();
    std::thread::spawn(move || {
        let built = WebviewWindowBuilder::from_config(&app, &app.config().app.windows[0]).and_then(|b| b.build());
        let Ok(window) = built.inspect_err(|e| log::error!("dashboard: {e}")) else { return };
        let _ = app.run_on_main_thread(move || {
            platform::exclude_window(&window);
            let _ = window.show();
            let _ = window.set_focus();
        });
    });
}

#[cfg(target_os = "macos")]
fn spawn_updater(app: AppHandle) {
    use std::time::Duration;
    let idle = || {
        let (tx, rx) = std::sync::mpsc::channel();
        engine::post(move |nyx| {
            let _ = tx.send(nyx.state == State::Idle);
        });
        rx.recv().unwrap_or(false)
    };
    std::thread::spawn(move || loop {
        std::thread::sleep(Duration::from_secs(10));
        if let Some(dmg) = update::download(&app.package_info().version.to_string()) {
            // Restarting drops any cover, so wait until nothing is covered.
            while !idle() {
                std::thread::sleep(Duration::from_secs(30));
            }
            if update::install(&dmg).is_some() {
                app.restart();
            }
        }
        std::thread::sleep(Duration::from_secs(6 * 60 * 60));
    });
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
            let path = app.path().config_dir()?.join("Nyx/protected.json");
            tray::build(app.handle())?;
            let list = store::ProtectionList::load(path);
            let shortcut = list.hotkey.shortcut().or(store::HotkeySpec::STANDARD.shortcut());
            if let Err(e) = shortcut.map(|s| app.global_shortcut().register(s)).transpose() {
                log::error!("hotkey registration failed: {e}");
            }
            // Otherwise Nyx starts quietly in the tray: the dashboard opens only when it needs the user.
            let granted = platform::has_screen_permission() && platform::has_accessibility_permission();
            let needs_user = !granted || list.load_failed || list.apps.is_empty();
            engine::start(app.handle().clone(), list);
            #[cfg(target_os = "macos")]
            if !cfg!(debug_assertions) {
                spawn_updater(app.handle().clone());
            }
            if needs_user {
                show_dashboard(app.handle());
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building Nyx")
        .run(|_app, event| match event {
            // Closing the dashboard must not quit Nyx; only Quit, which passes an exit code, does.
            RunEvent::ExitRequested { code: None, api, .. } => api.prevent_exit(),
            // Opening Nyx again from Spotlight or Finder is the way in when the menu bar hides the owl.
            #[cfg(target_os = "macos")]
            RunEvent::Reopen { .. } => show_dashboard(_app),
            _ => {}
        });
}
