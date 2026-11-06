use crate::store::ProtectedApp;
use std::path::{Path, PathBuf};

pub struct Installed {
    pub id: String,
    pub name: String,
    pub path: PathBuf,
}

pub fn pickable() -> Vec<Installed> {
    vec![]
}

pub fn app_at(_path: &Path) -> Option<Installed> {
    None
}

pub fn icon_png(_path: &Path) -> Option<Vec<u8>> {
    None
}

pub fn protected_icon(_app: &ProtectedApp) -> Option<Vec<u8>> {
    None
}
