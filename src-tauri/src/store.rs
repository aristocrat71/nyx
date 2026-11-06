use crate::site::ProtectedSite;
use serde::{Deserialize, Serialize};

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
    }
}
