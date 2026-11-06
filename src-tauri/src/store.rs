use crate::site::ProtectedSite;
use serde::{Deserialize, Serialize};
use tauri_plugin_global_shortcut::{Code, Modifiers, Shortcut};
use std::{fs, io, path::{Path, PathBuf}};

const MAX_APPS: usize = 200;
const MAX_SITES: usize = 200;
const MAX_NAME: usize = 128;
const MAX_REQUIREMENT: usize = 2048;

/// `id` is the bundle id on macOS and the lowercase executable name elsewhere.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProtectedApp {
    #[serde(rename = "bundleID")]
    pub id: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub requirement: Option<String>,
}

impl ProtectedApp {
    fn is_well_formed(&self) -> bool {
        (1..=255).contains(&self.id.len())
            && self.name.chars().count() <= MAX_NAME
            && self.requirement.as_ref().is_none_or(|r| r.len() <= MAX_REQUIREMENT)
            && self.id.chars().all(|c| c.is_alphanumeric() || ".-_".contains(c))
    }
}

/// Carbon key code and modifier bits, kept from the Swift app so its file still loads.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HotkeySpec {
    pub key_code: u32,
    pub carbon_modifiers: u32,
}

pub const CMD: u32 = 0x100;
pub const SHIFT: u32 = 0x200;
pub const OPTION: u32 = 0x800;
pub const CONTROL: u32 = 0x1000;

impl HotkeySpec {
    pub const STANDARD: HotkeySpec = HotkeySpec { key_code: 37, carbon_modifiers: CONTROL | SHIFT };

    /// Real key code, real modifier bits, and at least one modifier that isn't shift.
    pub fn is_well_formed(&self) -> bool {
        self.key_code < 128
            && self.carbon_modifiers & !(CMD | SHIFT | OPTION | CONTROL) == 0
            && self.carbon_modifiers & (CMD | OPTION | CONTROL) != 0
    }
}

/// Carbon virtual key codes for letters and digits; a stored key outside them falls back to the default.
const KEYS: &[(u32, Code)] = &[
    (0, Code::KeyA), (11, Code::KeyB), (8, Code::KeyC), (2, Code::KeyD), (14, Code::KeyE), (3, Code::KeyF),
    (5, Code::KeyG), (4, Code::KeyH), (34, Code::KeyI), (38, Code::KeyJ), (40, Code::KeyK), (37, Code::KeyL),
    (46, Code::KeyM), (45, Code::KeyN), (31, Code::KeyO), (35, Code::KeyP), (12, Code::KeyQ), (15, Code::KeyR),
    (1, Code::KeyS), (17, Code::KeyT), (32, Code::KeyU), (9, Code::KeyV), (13, Code::KeyW), (7, Code::KeyX),
    (16, Code::KeyY), (6, Code::KeyZ), (29, Code::Digit0), (18, Code::Digit1), (19, Code::Digit2),
    (20, Code::Digit3), (21, Code::Digit4), (23, Code::Digit5), (22, Code::Digit6), (26, Code::Digit7),
    (28, Code::Digit8), (25, Code::Digit9),
];

impl HotkeySpec {
    pub fn shortcut(&self) -> Option<Shortcut> {
        let code = KEYS.iter().find(|(k, _)| *k == self.key_code)?.1;
        let mut mods = Modifiers::empty();
        for (bit, m) in [(CMD, Modifiers::SUPER), (SHIFT, Modifiers::SHIFT), (OPTION, Modifiers::ALT), (CONTROL, Modifiers::CONTROL)] {
            if self.carbon_modifiers & bit != 0 {
                mods |= m;
            }
        }
        self.is_well_formed().then(|| Shortcut::new(Some(mods), code))
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct File {
    apps: Vec<ProtectedApp>,
    hotkey: Option<HotkeySpec>,
    protection_enabled: Option<bool>,
    sites: Option<Vec<ProtectedSite>>,
}

#[derive(Debug, Default, PartialEq)]
pub struct Loaded {
    pub apps: Vec<ProtectedApp>,
    pub sites: Vec<ProtectedSite>,
    pub hotkey: Option<HotkeySpec>,
    pub dropped: usize,
    pub failed: bool,
}

/// Everything a hostile or corrupt file can influence. A stored "off" is never read
/// back: turning protection off takes an action this session, not a rewritten file.
pub fn decode(data: &[u8]) -> Loaded {
    let Ok(file) = serde_json::from_slice::<File>(data) else {
        return Loaded { failed: true, ..Default::default() };
    };
    let sites = file.sites.unwrap_or_default();
    let total = file.apps.len() + sites.len();
    let apps: Vec<_> = file.apps.into_iter().filter(ProtectedApp::is_well_formed).take(MAX_APPS).collect();
    let sites: Vec<_> = sites.into_iter().filter(ProtectedSite::is_well_formed).take(MAX_SITES).collect();
    Loaded {
        dropped: total - apps.len() - sites.len(),
        hotkey: file.hotkey.filter(HotkeySpec::is_well_formed),
        apps,
        sites,
        failed: false,
    }
}

pub struct ProtectionList {
    pub apps: Vec<ProtectedApp>,
    pub sites: Vec<ProtectedSite>,
    pub hotkey: HotkeySpec,
    pub enabled: bool,
    /// The unreadable file is left for the user to recover; the dashboard says so.
    pub load_failed: bool,
    path: PathBuf,
}

impl ProtectionList {
    pub fn load(path: PathBuf) -> Self {
        tighten(&path);
        let loaded = match fs::read(&path) {
            Ok(data) => decode(&data),
            Err(_) => Loaded::default(),
        };
        if loaded.failed {
            log::error!("could not decode protected.json");
        } else if loaded.dropped > 0 {
            log::error!("dropped {} malformed entries", loaded.dropped);
        }
        ProtectionList {
            apps: loaded.apps,
            sites: loaded.sites,
            hotkey: loaded.hotkey.unwrap_or(HotkeySpec::STANDARD),
            enabled: true,
            load_failed: loaded.failed,
            path,
        }
    }

    pub fn contains(&self, id: &str) -> bool {
        self.apps.iter().any(|a| a.id == id)
    }

    pub fn add(&mut self, id: &str, name: &str, requirement: Option<String>) {
        let app = ProtectedApp { id: id.into(), name: name.chars().take(MAX_NAME).collect(), requirement };
        if !self.contains(id) && app.is_well_formed() && self.apps.len() < MAX_APPS {
            self.apps.push(app);
            self.save();
        }
    }

    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
        self.save();
    }

    pub fn remove(&mut self, id: &str) {
        self.apps.retain(|a| a.id != id);
        self.save();
    }

    /// Returns the stored form, so the field can show what it kept.
    pub fn add_site(&mut self, raw: &str) -> Option<String> {
        let host = ProtectedSite::normalize(raw)?;
        if self.sites.iter().any(|s| s.host == host) || self.sites.len() >= MAX_SITES {
            return None;
        }
        self.sites.push(ProtectedSite { host: host.clone() });
        self.sites.sort_by(|a, b| a.host.cmp(&b.host));
        self.save();
        Some(host)
    }

    pub fn remove_site(&mut self, host: &str) {
        self.sites.retain(|s| s.host != host);
        self.save();
    }

    fn save(&mut self) {
        let file = File {
            apps: self.apps.clone(),
            hotkey: Some(self.hotkey),
            protection_enabled: Some(self.enabled),
            sites: Some(self.sites.clone()),
        };
        match write_private(&self.path, &serde_json::to_vec_pretty(&file).expect("plain data serializes")) {
            Ok(()) => self.load_failed = false,
            Err(e) => log::error!("could not save protected.json: {e}"),
        }
    }
}

/// Atomic, and owner-only on unix: which apps are protected is itself private.
fn write_private(path: &Path, data: &[u8]) -> io::Result<()> {
    let dir = path.parent().expect("file path has a parent");
    fs::create_dir_all(dir)?;
    let tmp = path.with_extension("json.tmp");
    fs::write(&tmp, data)?;
    tighten(&tmp);
    fs::rename(&tmp, path)?;
    tighten(path);
    Ok(())
}

/// Also run on launch, so files from installs that wrote them world-readable get fixed.
fn tighten(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Some(dir) = path.parent() {
            let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o700));
        }
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(json: &str) -> Loaded {
        decode(json.as_bytes())
    }

    #[test]
    fn swift_file_loads_and_garbage_is_reported() {
        let ok = d(r#"{"apps":[{"bundleID":"com.apple.TextEdit","name":"TextEdit",
            "requirement":"identifier \"com.apple.TextEdit\" and anchor apple"}],
            "hotkey":{"keyCode":37,"carbonModifiers":4608},"protectionEnabled":true}"#);
        assert!(!ok.failed && ok.dropped == 0 && ok.sites.is_empty());
        assert_eq!(ok.apps[0].requirement.as_deref(), Some(r#"identifier "com.apple.TextEdit" and anchor apple"#));
        assert_eq!(ok.hotkey, Some(HotkeySpec::STANDARD));
        for bad in ["", "{", "null", "[]", r#"{"apps":"x"}"#, r#"{"hotkey":{}}"#] {
            assert!(d(bad).failed, "{bad}");
        }
    }

    #[test]
    fn hostile_entries_are_dropped_and_capped() {
        let r = d(&format!(r#"{{"apps":[{{"bundleID":"com.apple.TextEdit","name":"TextEdit"}},
            {{"bundleID":"../../etc/passwd","name":"x"}},{{"bundleID":"","name":"x"}},
            {{"bundleID":"com.a b","name":"x"}},{{"bundleID":"{}","name":"x"}},
            {{"bundleID":"com.ok","name":"{}"}},{{"bundleID":"com.ok","name":"n","requirement":"{}"}}],
            "sites":[{{"host":"youtube.com"}},{{"host":"UPPER.com"}},{{"host":"you/tube.com"}}]}}"#,
            "a".repeat(256), "b".repeat(129), "x".repeat(2049)));
        assert_eq!(r.apps.iter().map(|a| a.id.as_str()).collect::<Vec<_>>(), ["com.apple.TextEdit"]);
        assert_eq!(r.sites, [ProtectedSite { host: "youtube.com".into() }]);
        assert_eq!(r.dropped, 8);
        let many: Vec<String> = (0..500).map(|n| format!(r#"{{"bundleID":"com.n{n}","name":"n"}}"#)).collect();
        assert_eq!(d(&format!(r#"{{"apps":[{}]}}"#, many.join(","))).apps.len(), MAX_APPS);
    }

    #[test]
    fn stored_off_and_hostile_hotkeys_are_ignored() {
        assert_eq!(d(r#"{"apps":[],"protectionEnabled":false}"#), Loaded::default());
        for (code, mods) in [(99999, 4608u32), (37, 0), (37, SHIFT), (37, u32::MAX)] {
            assert_eq!(d(&format!(r#"{{"apps":[],"hotkey":{{"keyCode":{code},"carbonModifiers":{mods}}}}}"#)).hotkey, None);
        }
        for mods in [CMD, CONTROL, OPTION, CMD | SHIFT, CONTROL | SHIFT] {
            assert!(HotkeySpec { key_code: 37, carbon_modifiers: mods }.is_well_formed());
        }
        let standard = HotkeySpec::STANDARD.shortcut().unwrap();
        assert_eq!(standard, Shortcut::new(Some(Modifiers::CONTROL | Modifiers::SHIFT), Code::KeyL));
        assert_eq!(HotkeySpec { key_code: 122, carbon_modifiers: CONTROL }.shortcut(), None);
    }

    #[test]
    fn saves_round_trip_owner_only() {
        let dir = std::env::temp_dir().join(format!("nyx-store-{}", std::process::id()));
        let path = dir.join("Nyx/protected.json");
        let mut list = ProtectionList::load(path.clone());
        list.add("com.apple.TextEdit", "TextEdit", None);
        assert_eq!(list.add_site("https://www.YouTube.com/watch").as_deref(), Some("youtube.com"));
        list.enabled = false;
        list.remove_site("nothing.com");
        let again = ProtectionList::load(path.clone());
        assert_eq!((again.apps.len(), again.sites.len(), again.enabled), (1, 1, true));
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        }
        let _ = fs::remove_dir_all(dir);
    }
}
