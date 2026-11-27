//! Updates the installed Nyx.app from the Nyx-update.dmg and its .sha256 every release publishes,
//! checked the same way install.sh checks them.
use std::path::{Path, PathBuf};
use std::process::Command;

const RELEASES: &str = "https://github.com/unravel-team/nyx/releases";

fn run(tool: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(tool).args(args).output().ok()?;
    out.status.success().then(|| String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn parse(version: &str) -> Option<(u64, u64, u64)> {
    let mut parts = version.split('.').map(|n| n.parse().ok());
    let v = (parts.next()??, parts.next()??, parts.next()??);
    parts.next().is_none().then_some(v)
}

/// The running bundle, when Nyx runs from one (not `bun tauri dev` or a bare binary).
fn bundle() -> Option<PathBuf> {
    let app = std::env::current_exe().ok()?.ancestors().nth(3)?.to_path_buf();
    (app.extension()? == "app").then_some(app)
}

/// Downloads the newest release if it is newer than `current`, returning the verified dmg.
pub fn download(current: &str) -> Option<PathBuf> {
    bundle()?;
    let latest = format!("{RELEASES}/latest");
    let url = run("/usr/bin/curl", &["-fsSLI", "-o", "/dev/null", "-w", "%{url_effective}", &latest])?;
    let (_, version) = url.rsplit_once("/tag/nyx-v")?;
    if parse(version)? <= parse(current)? {
        return None;
    }
    let dir = std::env::temp_dir().join("nyx-update");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).ok()?;
    let dmg = dir.join("Nyx.dmg");
    let source = format!("{RELEASES}/download/nyx-v{version}/Nyx-update.dmg");
    run("/usr/bin/curl", &["-fsSL", "-o", dmg.to_str()?, &source])?;
    let expected = run("/usr/bin/curl", &["-fsSL", &format!("{source}.sha256")])?;
    let actual = run("/usr/bin/shasum", &["-a", "256", dmg.to_str()?])?;
    let ok = expected.split_whitespace().next()? == actual.split_whitespace().next()?;
    if !ok {
        log::error!("update: checksum mismatch for nyx-v{version}");
    }
    ok.then_some(dmg)
}

/// Swaps the running bundle for the one in `dmg`; the old one is removed only once the new one is in place.
pub fn install(dmg: &Path) -> Option<()> {
    let app = bundle()?;
    let mnt = dmg.with_file_name("mnt");
    run("/usr/bin/hdiutil", &["attach", dmg.to_str()?, "-nobrowse", "-quiet", "-mountpoint", mnt.to_str()?])?;
    let staged = app.with_extension("app.new");
    let _ = std::fs::remove_dir_all(&staged);
    let copied = run("/usr/bin/ditto", &[mnt.join("Nyx.app").to_str()?, staged.to_str()?]);
    let _ = run("/usr/bin/hdiutil", &["detach", mnt.to_str()?, "-quiet"]);
    copied?;
    let old = app.with_extension("app.old");
    let _ = std::fs::remove_dir_all(&old);
    std::fs::rename(&app, &old).ok()?;
    if std::fs::rename(&staged, &app).is_err() {
        let _ = std::fs::rename(&old, &app);
        return None;
    }
    let _ = std::fs::remove_dir_all(&old);
    let _ = std::fs::remove_dir_all(dmg.parent()?);
    Some(())
}

/// True on the first launch of a version other than the last one launched, so once per update.
pub fn first_launch_after_update(dir: &Path, version: &str) -> bool {
    let file = dir.join("last-version");
    let last = std::fs::read_to_string(&file).ok();
    let _ = std::fs::create_dir_all(dir).and_then(|_| std::fs::write(&file, version));
    last.is_some_and(|v| v.trim() != version)
}

#[cfg(test)]
mod tests {
    use super::{first_launch_after_update, parse};

    #[test]
    fn only_a_new_version_counts_as_an_update() {
        let dir = std::env::temp_dir().join(format!("nyx-update-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        assert!(!first_launch_after_update(&dir, "0.1.1"));
        assert!(!first_launch_after_update(&dir, "0.1.1"));
        assert!(first_launch_after_update(&dir, "0.1.2"));
        assert!(!first_launch_after_update(&dir, "0.1.2"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn versions_compare_numerically() {
        assert!(parse("0.10.0") > parse("0.9.9"));
        assert!(parse("1.0.0") > parse("0.99.99"));
        assert_eq!(parse("0.2.0"), Some((0, 2, 0)));
        assert_eq!(parse("0.2.0-beta"), None);
        assert_eq!(parse("0.2"), None);
    }
}
