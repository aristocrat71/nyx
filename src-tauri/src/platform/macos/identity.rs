use super::App;
use objc2_core_foundation::{CFDictionary, CFNumber, CFRetained, CFString, CFURL};
use objc2_security::{
    kSecCSDoNotValidateResources, kSecGuestAttributePid, SecCSFlags, SecCode, SecRequirement, SecStaticCode,
};
use std::path::Path;
use std::ptr::NonNull;

// Code identity: a bundle id is self-asserted, so the designated requirement of the app
// the user picked is pinned and later claimants are checked against it.

pub fn designated_requirement(bundle: &Path) -> Option<String> {
    let code = static_code(bundle)?;
    let mut requirement: *mut SecRequirement = std::ptr::null_mut();
    let status = unsafe { SecCode::copy_designated_requirement(&code, SecCSFlags::empty(), NonNull::from(&mut requirement)) };
    let requirement = (status == 0).then(|| NonNull::new(requirement)).flatten().map(|r| unsafe { CFRetained::from_raw(r) })?;
    let mut text: *const CFString = std::ptr::null();
    let status = unsafe { requirement.copy_string(SecCSFlags::empty(), NonNull::from(&mut text)) };
    (status == 0).then(|| NonNull::new(text as *mut CFString)).flatten().map(|t| unsafe { CFRetained::from_raw(t) }.to_string())
}

/// Covered anyway on a mismatch, since refusing would be the one failure that shows content.
pub fn check_identity(app: &App, list: &crate::store::ProtectionList) {
    let pinned = list.apps.iter().find(|a| a.id == app.id).and_then(|a| a.requirement.as_deref());
    if pinned.is_some_and(|r| !process_satisfies(app.pid, r)) {
        log::error!("frontmost process does not match the pinned signing identity");
    }
}

fn process_satisfies(pid: i32, requirement: &str) -> bool {
    let Some(requirement) = parse_requirement(requirement) else { return false };
    let pid = CFNumber::new_i32(pid);
    let attributes = CFDictionary::from_slices(&[unsafe { kSecGuestAttributePid }], &[&*pid]);
    let mut code: *mut SecCode = std::ptr::null_mut();
    let status = unsafe { SecCode::copy_guest_with_attributes(None, Some(attributes.as_opaque()), SecCSFlags::empty(), NonNull::from(&mut code)) };
    let Some(code) = (status == 0).then(|| NonNull::new(code)).flatten().map(|c| unsafe { CFRetained::from_raw(c) }) else { return false };
    unsafe { code.check_validity(SecCSFlags::empty(), Some(&requirement)) == 0 }
}

/// An identity check, not an integrity audit: hashing every resource of a large bundle stalls the UI.
pub fn bundle_satisfies(bundle: &Path, requirement: &str) -> bool {
    let (Some(code), Some(requirement)) = (static_code(bundle), parse_requirement(requirement)) else { return false };
    unsafe { code.check_validity(SecCSFlags(kSecCSDoNotValidateResources), Some(&requirement)) == 0 }
}

fn static_code(bundle: &Path) -> Option<CFRetained<SecStaticCode>> {
    let url = CFURL::from_file_path(bundle)?;
    let mut code: *const SecStaticCode = std::ptr::null();
    let status = unsafe { SecStaticCode::create_with_path(&url, SecCSFlags::empty(), NonNull::from(&mut code)) };
    (status == 0).then(|| NonNull::new(code as *mut SecStaticCode)).flatten().map(|c| unsafe { CFRetained::from_raw(c) })
}

fn parse_requirement(text: &str) -> Option<CFRetained<SecRequirement>> {
    let mut requirement: *mut SecRequirement = std::ptr::null_mut();
    let status = unsafe { SecRequirement::create_with_string(&CFString::from_str(text), SecCSFlags::empty(), NonNull::from(&mut requirement)) };
    (status == 0).then(|| NonNull::new(requirement)).flatten().map(|r| unsafe { CFRetained::from_raw(r) })
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pinned_identity_accepts_the_real_app_only() {
        let textedit = Path::new("/System/Applications/TextEdit.app");
        let requirement = designated_requirement(textedit).expect("TextEdit is signed");
        assert!(requirement.contains(r#"identifier "com.apple.TextEdit""#));
        assert!(bundle_satisfies(textedit, &requirement));
        assert!(!bundle_satisfies(Path::new("/System/Library/CoreServices/Finder.app"), &requirement));
        assert!(!process_satisfies(std::process::id() as i32, &requirement));
        assert!(!bundle_satisfies(textedit, "not a requirement ((("));
        // A live process must satisfy its own requirement: the dynamic check rejects static-only flags.
        let mut cat = std::process::Command::new("/bin/cat").stdin(std::process::Stdio::piped()).spawn().unwrap();
        let own = designated_requirement(Path::new("/bin/cat")).unwrap();
        let ok = process_satisfies(cat.id() as i32, &own);
        cat.kill().unwrap();
        assert!(ok);
    }
}
