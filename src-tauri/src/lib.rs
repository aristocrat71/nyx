mod site;
mod store;

use tauri::{Manager, WindowEvent};

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);
            if let Some(dashboard) = app.get_webview_window("dashboard") {
                dashboard.show()?;
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            // The dashboard closes to the tray: hidden, never destroyed.
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running Nyx");
}
