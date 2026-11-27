use crate::engine::{self, State};
use crate::platform;
use serde::Serialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

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
    store_path: String,
    hotkey: String,
    platform: &'static str,
    notice: Option<&'static str>,
}

#[derive(Serialize)]
pub struct Row {
    id: String,
    name: String,
    path: String,
}

thread_local! {
    static PATHS: RefCell<HashMap<String, Option<PathBuf>>> = RefCell::default();
}

/// Icons load lazily from here as rows scroll into view, never all at once in a command reply.
pub fn icon(request: tauri::http::Request<Vec<u8>>, responder: tauri::UriSchemeResponder) {
    let path = percent_encoding::percent_decode_str(request.uri().path().trim_start_matches('/')).decode_utf8_lossy().into_owned();
    tauri::async_runtime::spawn_blocking(move || {
        let response = match platform::icon_png(Path::new(&path)) {
            Some(png) => tauri::http::Response::builder().header("Content-Type", "image/png").body(png),
            None => tauri::http::Response::builder().status(404).body(Vec::new()),
        };
        responder.respond(response.expect("static response parts"));
    });
}

#[tauri::command]
pub fn snapshot() -> Option<Snapshot> {
    engine::with(|nyx| Snapshot {
        apps: nyx.list.apps.iter().map(|app| Row {
            path: PATHS.with(|c| c.borrow_mut().entry(app.id.clone()).or_insert_with(|| platform::protected_path(app)).clone())
                .map_or_else(String::new, |p| p.to_string_lossy().into_owned()),
            id: app.id.clone(),
            name: app.name.clone(),
        }).collect(),
        sites: nyx.list.sites.iter().map(|s| s.host.clone()).collect(),
        enabled: nyx.list.enabled,
        state: nyx.state,
        screen_permission: platform::has_screen_permission(),
        accessibility_permission: platform::has_accessibility_permission(),
        load_failed: nyx.list.load_failed,
        store_path: nyx.list.path().display().to_string(),
        hotkey: nyx.list.hotkey.label(cfg!(target_os = "macos")),
        platform: std::env::consts::OS,
        notice: platform::notice(),
    })
}

/// Off the main thread: walking the Applications folders must not stall the overlays.
#[tauri::command]
pub async fn pickable(exclude: Vec<String>) -> Vec<Row> {
    platform::pickable().into_iter().filter(|a| !exclude.contains(&a.id)).map(|a| Row {
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
pub fn normalize_site(raw: String) -> Option<String> {
    crate::site::ProtectedSite::normalize(&raw)
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
        "changelog" => platform::open_url(concat!("https://github.com/unravel-team/nyx/releases/tag/nyx-v", env!("CARGO_PKG_VERSION"))),
        _ => {}
    }
}
