use super::App;
use std::path::Path;

pub fn designated_requirement(_exe: &Path) -> Option<String> {
    None
}

pub fn check_identity(_app: &App, _list: &crate::store::ProtectionList) {}
