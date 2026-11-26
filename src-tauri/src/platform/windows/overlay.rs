use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;
use windows::core::{w, BOOL};
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED, DWMWA_EXTENDED_FRAME_BOUNDS};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, FillRect, GetStockObject, SetStretchBltMode, StretchDIBits, BITMAPINFO, BITMAPINFOHEADER,
    BLACK_BRUSH, DIB_RGB_COLORS, HALFTONE, HBRUSH, PAINTSTRUCT, SRCCOPY,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, EnumWindows, GetClientRect, IsIconic, IsWindowVisible, RegisterClassW,
    SetLayeredWindowAttributes, SetWindowPos, ShowWindow, HTTRANSPARENT, HWND_TOPMOST, LWA_ALPHA, SWP_NOACTIVATE,
    SWP_NOZORDER, SWP_SHOWWINDOW, SET_WINDOW_POS_FLAGS, SW_HIDE, WINDOW_EX_STYLE, WM_NCHITTEST, WM_PAINT, WNDCLASSW, WS_EX_LAYERED, WS_EX_NOACTIVATE,
    WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_EX_TRANSPARENT, WS_POPUP,
};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Target {
    pub hwnd: isize,
    pub frame: RECT,
}

/// Every visible window the process owns, menus and tooltips included: they are top-level windows too.
pub fn windows_of(pid: i32) -> Vec<Target> {
    let mut found = (pid as u32, Vec::new());
    let _ = unsafe { EnumWindows(Some(collect), LPARAM(&mut found as *mut _ as isize)) };
    found.1
}

unsafe extern "system" fn collect(hwnd: HWND, data: LPARAM) -> BOOL {
    let (pid, found) = unsafe { &mut *(data.0 as *mut (u32, Vec<Target>)) };
    if super::window_pid(hwnd) == *pid && unsafe { IsWindowVisible(hwnd).as_bool() && !IsIconic(hwnd).as_bool() } {
        let mut cloaked = 0u32;
        let _ = unsafe { DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &mut cloaked as *mut _ as _, 4) };
        let mut frame = RECT::default();
        let sized = unsafe { DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &mut frame as *mut _ as _, 16) };
        if cloaked == 0 && sized.is_ok() && frame.right > frame.left && frame.bottom > frame.top {
            found.push(Target { hwnd: hwnd.0 as isize, frame });
        }
    }
    true.into()
}

/// Layered and click-through, so input reaches the real app and nothing here can take focus.
pub(super) fn overlay_window(class: windows::core::PCWSTR, extra: WINDOW_EX_STYLE) -> HWND {
    let style = WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_LAYERED | extra;
    let instance = unsafe { GetModuleHandleW(None) }.ok().map(Into::into);
    unsafe { CreateWindowExW(style, class, w!(""), WS_POPUP, 0, 0, 0, 0, None, None, instance, None) }
        .expect("overlay window")
}

/// Raised only when first shown: a move never reorders, so a mirror stays above the cover beneath it.
pub(super) fn place(hwnd: HWND, r: RECT, raise: bool) {
    let flags = SWP_NOACTIVATE | SWP_SHOWWINDOW | if raise { SET_WINDOW_POS_FLAGS(0) } else { SWP_NOZORDER };
    let _ = unsafe { SetWindowPos(hwnd, Some(HWND_TOPMOST), r.left, r.top, r.right - r.left, r.bottom - r.top, flags) };
}

const BLEED_WHILE_MOVING: i32 = 24;
const SETTLE_TICKS: u8 = 6;
const SPARES: usize = 8;

struct Cover {
    hwnd: HWND,
    last: RECT,
    placed: RECT,
    moving: u8,
}

#[derive(Default)]
pub struct Placeholders {
    covers: HashMap<isize, Cover>,
    spares: Vec<HWND>,
}

impl Placeholders {
    pub fn cover(&mut self, targets: &[Target]) {
        for t in targets {
            let fresh = !self.covers.contains_key(&t.hwnd);
            let cover = self.covers.entry(t.hwnd).or_insert_with(|| Cover {
                hwnd: self.spares.pop().unwrap_or_else(placeholder_window),
                last: t.frame,
                placed: RECT::default(),
                moving: 0,
            });
            cover.moving = if fresh || cover.last == t.frame { cover.moving.saturating_sub(1) } else { SETTLE_TICKS };
            cover.last = t.frame;
            // A cover in motion holds a margin, so one tick of lag never uncovers an edge.
            let b = if cover.moving > 0 { BLEED_WHILE_MOVING } else { 0 };
            let f = t.frame;
            let want = RECT { left: f.left - b, top: f.top - b, right: f.right + b, bottom: f.bottom + b };
            if want != cover.placed {
                place(cover.hwnd, want, cover.placed == RECT::default());
                cover.placed = want;
            }
        }
        let live: HashSet<isize> = targets.iter().map(|t| t.hwnd).collect();
        let gone: Vec<isize> = self.covers.keys().filter(|id| !live.contains(id)).copied().collect();
        for id in gone {
            let cover = self.covers.remove(&id).expect("listed above");
            self.retire(cover.hwnd);
        }
    }

    pub fn clear(&mut self) {
        let covers: Vec<HWND> = self.covers.drain().map(|(_, c)| c.hwnd).collect();
        covers.into_iter().for_each(|hwnd| self.retire(hwnd));
    }

    fn retire(&mut self, hwnd: HWND) {
        let _ = unsafe { ShowWindow(hwnd, SW_HIDE) };
        if self.spares.len() < SPARES {
            self.spares.push(hwnd);
        }
    }
}

fn placeholder_window() -> HWND {
    static CLASS: OnceLock<u16> = OnceLock::new();
    CLASS.get_or_init(|| {
        let class = WNDCLASSW { lpfnWndProc: Some(placeholder_proc), lpszClassName: w!("NyxPlaceholder"), ..Default::default() };
        unsafe { RegisterClassW(&class) }
    });
    let hwnd = overlay_window(w!("NyxPlaceholder"), WINDOW_EX_STYLE(0));
    // 254, not 255: an opaque window makes Chromium treat the app beneath as occluded and stop painting.
    let _ = unsafe { SetLayeredWindowAttributes(hwnd, COLORREF(0), 254, LWA_ALPHA) };
    hwnd
}

/// The caption PNG is @2x for 522x169 points; composited onto black once, so painting is one blit.
fn caption() -> &'static (Vec<u8>, i32, i32) {
    static CAPTION: OnceLock<(Vec<u8>, i32, i32)> = OnceLock::new();
    CAPTION.get_or_init(|| {
        let image = tauri::image::Image::from_bytes(include_bytes!("../../../assets/caption.png")).expect("caption decodes");
        let bgr = image.rgba().chunks(4).flat_map(|p| {
            let a = p[3] as u16;
            [(p[2] as u16 * a / 255) as u8, (p[1] as u16 * a / 255) as u8, (p[0] as u16 * a / 255) as u8, 255]
        });
        (bgr.collect(), image.width() as i32, image.height() as i32)
    })
}

unsafe extern "system" fn placeholder_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_NCHITTEST => LRESULT(HTTRANSPARENT as isize),
        WM_PAINT => {
            let mut ps = PAINTSTRUCT::default();
            let dc = unsafe { BeginPaint(hwnd, &mut ps) };
            let mut client = RECT::default();
            let _ = unsafe { GetClientRect(hwnd, &mut client) };
            unsafe { FillRect(dc, &client, HBRUSH(GetStockObject(BLACK_BRUSH).0)) };
            let (pixels, w, h) = caption();
            let scale = unsafe { GetDpiForWindow(hwnd) } as i32;
            let (dw, dh) = (522 * scale / 96, 169 * scale / 96);
            let (cw, ch) = (client.right, client.bottom);
            if cw >= dw + 48 * scale / 96 && ch >= dh + 96 * scale / 96 {
                let mut info = BITMAPINFO::default();
                info.bmiHeader = BITMAPINFOHEADER { biSize: 40, biWidth: *w, biHeight: -h, biPlanes: 1, biBitCount: 32, ..Default::default() };
                unsafe {
                    SetStretchBltMode(dc, HALFTONE);
                    StretchDIBits(dc, (cw - dw) / 2, (ch - dh) / 2, dw, dh, 0, 0, *w, *h, Some(pixels.as_ptr() as _), &info, DIB_RGB_COLORS, SRCCOPY);
                }
            }
            let _ = unsafe { EndPaint(hwnd, &ps) };
            LRESULT(0)
        }
        _ => unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) },
    }
}
