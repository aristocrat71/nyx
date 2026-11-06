use crate::engine::{self, State};
use crate::platform;
use base64::Engine as _;
use serde::Serialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::path::Path;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    apps: Vec<Row>,
    sites: Vec<String>,
    enabled: bool,
    state: State,
    screen_permission: bool,
    accessibility_permission: bool,
    load_failed: bool,
    hotkey: String,
}

#[derive(Serialize)]
pub struct Row {
    id: String,
    name: String,
    path: String,
    icon: Option<String>,
}

thread_local! {
    static ICONS: RefCell<HashMap<String, Option<String>>> = RefCell::default();
}

fn data_url(png: Vec<u8>) -> String {
    format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(png))
}

#[tauri::command]
pub fn snapshot() -> Option<Snapshot> {
    engine::with(|nyx| Snapshot {
        apps: nyx.list.apps.iter().map(|app| Row {
            icon: ICONS.with(|c| c.borrow_mut().entry(app.id.clone()).or_insert_with(|| platform::protected_icon(app).map(data_url)).clone()),
            id: app.id.clone(),
            name: app.name.clone(),
            path: String::new(),
        }).collect(),
        sites: nyx.list.sites.iter().map(|s| s.host.clone()).collect(),
        enabled: nyx.list.enabled,
        state: nyx.state,
        screen_permission: platform::has_screen_permission(),
        accessibility_permission: platform::has_accessibility_permission(),
        load_failed: nyx.list.load_failed,
        hotkey: nyx.list.hotkey.label(cfg!(target_os = "macos")),
    })
}

/// Off the main thread: walking the Applications folders must not stall the overlays.
#[tauri::command]
pub async fn pickable(exclude: Vec<String>) -> Vec<Row> {
    platform::pickable().into_iter().filter(|a| !exclude.contains(&a.id)).map(|a| Row {
        icon: platform::icon_png(&a.path).map(data_url),
        path: a.path.to_string_lossy().into_owned(),
        id: a.id,
        name: a.name,
    }).collect()
}

/// The UI only names a bundle; its id, name and signing identity are read here, not taken from the UI.
#[tauri::command]
pub fn add_app(path: String) {
    let Some(app) = platform::app_at(Path::new(&path)) else { return };
    let requirement = platform::designated_requirement(&app.path);
    engine::with(|nyx| {
        nyx.list.add(&app.id, &app.name, requirement);
        nyx.evaluate();
    });
}

#[tauri::command]
pub fn remove_app(id: String) {
    engine::with(|nyx| {
        nyx.list.remove(&id);
        nyx.evaluate();
    });
}

#[tauri::command]
pub fn add_site(raw: String) -> Option<String> {
    engine::with(|nyx| {
        let host = nyx.list.add_site(&raw);
        nyx.evaluate();
        host
    })
    .flatten()
}

#[tauri::command]
pub fn remove_site(host: String) {
    engine::with(|nyx| {
        nyx.list.remove_site(&host);
        nyx.evaluate();
    });
}

#[tauri::command]
pub fn open_link(target: String) {
    match target.as_str() {
        "screen" => platform::open_screen_settings(),
        "accessibility" => platform::open_accessibility_settings(),
        "unravel" => platform::open_url("https://unravel.tech"),
        _ => {}
    }
}
