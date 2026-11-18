use super::{app_for_pid, identity::satisfies, window_pid};
use crate::store::ProtectedApp;
use std::path::{Path, PathBuf};
use windows::core::{BOOL, HSTRING};
use windows::Win32::Foundation::{HWND, LPARAM};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use windows::Win32::Graphics::Gdi::{
    DeleteObject, GetDC, GetDIBits, ReleaseDC, BITMAPINFO, BITMAPINFOHEADER, DIB_RGB_COLORS, HGDIOBJ,
};
use windows::Win32::Storage::FileSystem::FILE_FLAGS_AND_ATTRIBUTES;
use windows::Win32::UI::Shell::{SHGetFileInfoW, SHFILEINFOW, SHGFI_ICON, SHGFI_LARGEICON};
use windows::Win32::UI::WindowsAndMessaging::{
    DestroyIcon, EnumWindows, GetIconInfo, GetWindow, GetWindowLongW, GetWindowTextLengthW, IsWindowVisible, GWL_EXSTYLE,
    GW_OWNER, ICONINFO, WS_EX_TOOLWINDOW,
};

pub struct Installed {
    pub id: String,
    pub name: String,
    pub path: PathBuf,
}

/// ponytail: running apps with a real window only, as the first macOS version did. Upgrade: add
/// Start-menu shortcuts so apps that are not open can be picked too.
pub fn pickable() -> Vec<Installed> {
    let mut pids: Vec<u32> = Vec::new();
    let _ = unsafe { EnumWindows(Some(collect), LPARAM(&mut pids as *mut _ as isize)) };
    let mut apps: Vec<Installed> = Vec::new();
    for app in pids.into_iter().filter(|p| *p != std::process::id()).filter_map(app_for_pid) {
        if !apps.iter().any(|a| a.id == app.id) {
            apps.extend(app.path.map(|path| Installed { id: app.id, name: app.name, path }));
        }
    }
    apps.sort_by_key(|a| a.name.to_lowercase());
    apps
}

/// Visible, unowned, titled and not a tool window: what the taskbar would show.
unsafe extern "system" fn collect(hwnd: HWND, data: LPARAM) -> BOOL {
    let pids = unsafe { &mut *(data.0 as *mut Vec<u32>) };
    let mut cloaked = 0u32;
    let _ = unsafe { DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &mut cloaked as *mut _ as _, 4) };
    let tool = unsafe { GetWindowLongW(hwnd, GWL_EXSTYLE) } as u32 & WS_EX_TOOLWINDOW.0 != 0;
    let owned = unsafe { GetWindow(hwnd, GW_OWNER) }.is_ok_and(|owner| !owner.is_invalid());
    if unsafe { IsWindowVisible(hwnd).as_bool() && GetWindowTextLengthW(hwnd) > 0 } && cloaked == 0 && !tool && !owned {
        let pid = window_pid(hwnd);
        if !pids.contains(&pid) {
            pids.push(pid);
        }
    }
    true.into()
}

pub fn app_at(path: &Path) -> Option<Installed> {
    if !path.extension().is_some_and(|e| e.eq_ignore_ascii_case("exe")) || !path.is_file() {
        return None;
    }
    Some(Installed {
        id: path.file_name()?.to_string_lossy().to_lowercase(),
        name: path.file_stem()?.to_string_lossy().into_owned(),
        path: path.into(),
    })
}

/// The pinned path, never whichever exe happens to share the name.
pub fn protected_path(app: &ProtectedApp) -> Option<PathBuf> {
    let path = PathBuf::from(app.requirement.as_deref()?.strip_prefix("path:")?);
    (path.is_file() && satisfies(&path, app.requirement.as_deref()?)).then_some(path)
}

pub fn icon_png(path: &Path) -> Option<Vec<u8>> {
    let mut info = SHFILEINFOW::default();
    let flags = SHGFI_ICON | SHGFI_LARGEICON;
    let size = std::mem::size_of::<SHFILEINFOW>() as u32;
    unsafe { SHGetFileInfoW(&HSTRING::from(path.as_os_str()), FILE_FLAGS_AND_ATTRIBUTES(0), Some(&mut info), size, flags) };
    if info.hIcon.is_invalid() {
        return None;
    }
    let mut icon = ICONINFO::default();
    let read = unsafe { GetIconInfo(info.hIcon, &mut icon) };
    let pixels = read.ok().and_then(|_| bitmap_rgba(icon.hbmColor));
    unsafe {
        let _ = DeleteObject(HGDIOBJ(icon.hbmColor.0));
        let _ = DeleteObject(HGDIOBJ(icon.hbmMask.0));
        let _ = DestroyIcon(info.hIcon);
    }
    let (rgba, w, h) = pixels?;
    let mut png = Vec::new();
    let mut encoder = png::Encoder::new(&mut png, w, h);
    encoder.set_color(png::ColorType::Rgba);
    encoder.write_header().ok()?.write_image_data(&rgba).ok()?;
    Some(png)
}

fn bitmap_rgba(bitmap: windows::Win32::Graphics::Gdi::HBITMAP) -> Option<(Vec<u8>, u32, u32)> {
    let (w, h) = (32u32, 32u32);
    let mut info = BITMAPINFO::default();
    info.bmiHeader = BITMAPINFOHEADER { biSize: 40, biWidth: w as i32, biHeight: -(h as i32), biPlanes: 1, biBitCount: 32, ..Default::default() };
    let mut bgra = vec![0u8; (w * h * 4) as usize];
    let dc = unsafe { GetDC(None) };
    let lines = unsafe { GetDIBits(dc, bitmap, 0, h, Some(bgra.as_mut_ptr() as _), &mut info, DIB_RGB_COLORS) };
    unsafe { ReleaseDC(None, dc) };
    if lines == 0 {
        return None;
    }
    // Old icons carry no alpha at all; treat those as fully opaque.
    let opaque = bgra.chunks(4).all(|p| p[3] == 0);
    for p in bgra.chunks_mut(4) {
        p.swap(0, 2);
        if opaque {
            p[3] = 255;
        }
    }
    Some((bgra, w, h))
}
