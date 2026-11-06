use super::App;
use std::path::Path;

// Windows and Linux: pins the executable's full path, so a same-named impostor elsewhere does not match.
// ponytail: upgrade to signer pinning (Authenticode, package signatures) for apps that move on update.

pub fn designated_requirement(exe: &Path) -> Option<String> {
    Some(format!("path:{}", exe.to_string_lossy().to_lowercase()))
}

pub(super) fn satisfies(exe: &Path, requirement: &str) -> bool {
    requirement.strip_prefix("path:") == Some(exe.to_string_lossy().to_lowercase().as_str())
}

/// Covered anyway on a mismatch, since refusing would be the one failure that shows content.
pub fn check_identity(app: &App, list: &crate::store::ProtectionList) {
    let pinned = list.apps.iter().find(|a| a.id == app.id).and_then(|a| a.requirement.as_deref());
    if let (Some(pinned), Some(path)) = (pinned, &app.path) {
        if !satisfies(path, pinned) {
            log::error!("frontmost process is not the executable that was protected");
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn only_the_pinned_path_satisfies() {
        let pinned = super::designated_requirement(std::path::Path::new(r"C:\Apps\Slack\slack.exe")).unwrap();
        assert!(super::satisfies(std::path::Path::new(r"c:\apps\slack\SLACK.exe"), &pinned));
        assert!(!super::satisfies(std::path::Path::new(r"C:\Users\x\Downloads\slack.exe"), &pinned));
    }
}
