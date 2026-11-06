#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Tab {
    pub host: Option<String>,
    pub title: Option<String>,
}

pub fn is_browser(_id: &str) -> bool {
    false
}

pub fn browser_tab(_pid: i32) -> Option<Tab> {
    None
}

pub fn has_accessibility_permission() -> bool {
    true
}

pub fn open_accessibility_settings() {}
