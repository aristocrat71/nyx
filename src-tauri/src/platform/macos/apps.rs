use super::identity::bundle_satisfies;
use crate::store::ProtectedApp;
use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::AllocAnyThread;
use objc2_app_kit::{
    NSApplicationActivationPolicy, NSBitmapImageFileType, NSBitmapImageRep, NSRunningApplication, NSWorkspace,
};
use objc2_foundation::{NSBundle, NSDictionary, NSFileManager, NSNumber, NSPoint, NSRect, NSSize, NSString, NSURL};
use std::path::{Path, PathBuf};

/// An app the picker can offer: installed in an Applications folder, or running from anywhere.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Installed {
    pub id: String,
    pub name: String,
    pub path: PathBuf,
}

/// Running apps come first, so a protected app is pinned to the code actually in use.
pub fn pickable() -> Vec<Installed> {
    let me = NSRunningApplication::currentApplication().processIdentifier();
    let running = NSWorkspace::sharedWorkspace().runningApplications().iter().filter_map(|app| {
        if app.activationPolicy() != NSApplicationActivationPolicy::Regular || app.processIdentifier() == me {
            return None;
        }
        let path = app.bundleURL()?.to_file_path()?;
        let id = app.bundleIdentifier()?.to_string();
        Some(Installed { name: app.localizedName().map_or_else(|| id.clone(), |n| n.to_string()), id, path })
    }).collect::<Vec<_>>();
    let home = std::env::var("HOME").unwrap_or_default() + "/Applications";
    let mut found = Vec::new();
    for root in ["/Applications", "/System/Applications", &home] {
        scan(Path::new(root), 0, &mut found);
    }
    let mut all: Vec<Installed> = Vec::new();
    for app in running.into_iter().chain(found) {
        if !all.iter().any(|a| a.id == app.id) {
            all.push(app);
        }
    }
    all.sort_by_key(|a| a.name.to_lowercase());
    all
}

/// Two levels: Utilities-style subfolders count, nothing deeper does.
fn scan(dir: &Path, depth: usize, found: &mut Vec<Installed>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for path in entries.flatten().map(|e| e.path()) {
        if path.file_name().is_some_and(|n| n.to_string_lossy().starts_with('.')) {
            continue;
        }
        if path.extension().is_some_and(|e| e == "app") {
            found.extend(app_at(&path));
        } else if depth + 1 < 2 && path.is_dir() {
            scan(&path, depth + 1, found);
        }
    }
}

/// Menu-bar-only and faceless apps never come to the front, so protecting one would do nothing.
pub fn app_at(path: &Path) -> Option<Installed> {
    let bundle = NSBundle::bundleWithURL(&*NSURL::from_file_path(path)?)?;
    let id = bundle.bundleIdentifier()?.to_string();
    let flag = |key: &str| {
        bundle.objectForInfoDictionaryKey(&NSString::from_str(key)).is_some_and(|v| match v.downcast::<NSNumber>() {
            Ok(n) => n.boolValue(),
            Err(v) => v.downcast::<NSString>().is_ok_and(|s| ["1", "yes", "true"].contains(&s.to_string().to_lowercase().as_str())),
        })
    };
    if flag("LSUIElement") || flag("LSBackgroundOnly") {
        return None;
    }
    let shown = NSFileManager::defaultManager().displayNameAtPath(&NSString::from_str(&path.to_string_lossy()));
    let name = shown.to_string().trim_end_matches(".app").to_string();
    Some(Installed { id, name, path: path.into() })
}

/// LaunchServices hands back whichever bundle claims the id, so an icon only comes
/// from one that satisfies the identity pinned when the app was added.
pub fn protected_icon(app: &ProtectedApp) -> Option<Vec<u8>> {
    let url = NSWorkspace::sharedWorkspace().URLForApplicationWithBundleIdentifier(&NSString::from_str(&app.id))?;
    let path = url.to_file_path()?;
    if app.requirement.as_deref().is_some_and(|r| !bundle_satisfies(&path, r)) {
        log::error!("bundle claiming a protected id does not match its pinned identity");
        return None;
    }
    icon_png(&path)
}

pub fn icon_png(path: &Path) -> Option<Vec<u8>> {
    let image = NSWorkspace::sharedWorkspace().iconForFile(&NSString::from_str(&path.to_string_lossy()));
    let mut rect = NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(64.0, 64.0));
    let cg = unsafe { image.CGImageForProposedRect_context_hints(&mut rect, None, None) }?;
    let rep = NSBitmapImageRep::initWithCGImage(NSBitmapImageRep::alloc(), &cg);
    let props: Retained<NSDictionary<_, AnyObject>> = NSDictionary::new();
    let png = unsafe { rep.representationUsingType_properties(NSBitmapImageFileType::PNG, &props) }?;
    Some(png.to_vec())
}

#[cfg(test)]
mod tests {
    #[test]
    fn picker_finds_installed_apps_with_icons() {
        let apps = super::pickable();
        let textedit = apps.iter().find(|a| a.id == "com.apple.TextEdit").expect("TextEdit is installed");
        assert_eq!(textedit.name, "TextEdit");
        assert!(super::icon_png(&textedit.path).is_some_and(|png| png.starts_with(b"\x89PNG")));
        assert!(apps.windows(2).all(|w| w[0].name.to_lowercase() <= w[1].name.to_lowercase()));
    }
}
