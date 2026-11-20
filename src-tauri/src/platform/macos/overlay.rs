use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::{AllocAnyThread, MainThreadMarker};
use objc2_app_kit::{
    NSBackingStoreType, NSColor, NSImage, NSImageScaling, NSImageView, NSScreen, NSWindow,
    NSWindowCollectionBehavior, NSWindowStyleMask,
};
use objc2_core_foundation::{CFDictionary, CGRect};
use objc2_core_graphics::{
    CGRectMakeWithDictionaryRepresentation, CGWindowLevelForKey, CGWindowLevelKey, CGWindowListCopyWindowInfo,
    CGWindowListOption,
};
use objc2_foundation::{NSArray, NSData, NSDictionary, NSNumber, NSPoint, NSRect, NSSize, NSString};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Target {
    pub id: u32,
    pub layer: i32,
    pub frame: CGRect,
}

/// Every on-screen window `pid` owns, at every layer: menus and tooltips need covering too.
pub fn windows_of(pid: i32) -> Vec<Target> {
    let options = CGWindowListOption::OptionOnScreenOnly | CGWindowListOption::ExcludeDesktopElements;
    let Some(list) = CGWindowListCopyWindowInfo(options, 0) else { return vec![] };
    let list: &NSArray<NSDictionary<NSString, AnyObject>> = unsafe { &*(&*list as *const _ as *const _) };
    let num = |info: &NSDictionary<NSString, AnyObject>, key: &str| {
        info.objectForKey(&NSString::from_str(key)).and_then(|v| v.downcast::<NSNumber>().ok())
    };
    list.iter()
        .filter(|info| num(info, "kCGWindowOwnerPID").is_some_and(|p| p.intValue() == pid))
        .filter(|info| num(info, "kCGWindowAlpha").is_none_or(|a| a.doubleValue() > 0.0))
        .filter_map(|info| {
            let bounds = info.objectForKey(&NSString::from_str("kCGWindowBounds"))?;
            let mut frame = CGRect::default();
            let dict: &CFDictionary = unsafe { &*(Retained::as_ptr(&bounds) as *const CFDictionary) };
            let ok = unsafe { CGRectMakeWithDictionaryRepresentation(Some(dict), &mut frame) };
            if !ok || frame.size.width < 1.0 || frame.size.height < 1.0 {
                return None;
            }
            Some(Target {
                id: num(&info, "kCGWindowNumber")?.intValue() as u32,
                layer: num(&info, "kCGWindowLayer")?.intValue(),
                frame,
            })
        })
        .collect()
}

// Overlays: black placeholders viewers see, driven off CGWindowList rather than the
// capture stream, so a failing mirror degrades to "hidden", never "visible".

fn ceiling() -> isize {
    CGWindowLevelForKey(CGWindowLevelKey::ScreenSaverWindowLevelKey) as isize - 1
}

/// One level above the covered window and no higher: the levels over an ordinary
/// window hold the Dock, the switcher and the menu bar. Never reaches the screen saver.
fn placeholder_level(layer: i32) -> isize {
    (layer as isize).min(ceiling() - 2) + 1
}

pub(super) fn mirror_level(targets: &[Target]) -> isize {
    let top = targets.iter().map(|t| placeholder_level(t.layer)).max().unwrap_or(placeholder_level(0));
    (top + 1).min(ceiling())
}

/// CGWindowList is top-left-origin; AppKit is bottom-left of the screen with the menu bar.
pub(super) fn appkit_rect(cg: CGRect, primary_height: f64) -> NSRect {
    NSRect::new(NSPoint::new(cg.origin.x, primary_height - cg.origin.y - cg.size.height), cg.size)
}

pub(super) fn primary_height(mtm: MainThreadMarker) -> Option<f64> {
    NSScreen::screens(mtm).firstObject().map(|s| s.frame().size.height).filter(|h| *h > 0.0)
}

/// Non-opaque so macOS never reports the covered window as occluded: Chromium apps
/// stop rendering when occluded, which would freeze the mirror.
pub(super) fn overlay_window(mtm: MainThreadMarker, level: isize) -> Retained<NSWindow> {
    let window = unsafe {
        NSWindow::initWithContentRect_styleMask_backing_defer(
            mtm.alloc(), NSRect::ZERO, NSWindowStyleMask::Borderless, NSBackingStoreType::Buffered, false,
        )
    };
    unsafe { window.setReleasedWhenClosed(false) };
    window.setOpaque(false);
    window.setBackgroundColor(Some(&NSColor::clearColor()));
    window.setHasShadow(false);
    window.setIgnoresMouseEvents(true);
    window.setLevel(level);
    window.setCollectionBehavior(
        NSWindowCollectionBehavior::CanJoinAllSpaces
            | NSWindowCollectionBehavior::FullScreenAuxiliary
            | NSWindowCollectionBehavior::IgnoresCycle,
    );
    window
}

const CAPTION: &[u8] = include_bytes!("../../../assets/caption.png");
const CAPTION_SIZE: NSSize = NSSize::new(522.0, 169.0);
const BLEED_WHILE_MOVING: f64 = 24.0;
const SETTLE_TICKS: u8 = 6;
const SPARES: usize = 8;

struct Cover {
    window: Retained<NSWindow>,
    last: NSRect,
    moving: u8,
}

#[derive(Default)]
pub struct Placeholders {
    covers: HashMap<u32, Cover>,
    spares: Vec<Retained<NSWindow>>,
}

impl Placeholders {
    pub fn cover(&mut self, targets: &[Target]) {
        let mtm = MainThreadMarker::new().expect("overlays live on the main thread");
        let Some(height) = primary_height(mtm) else { return };
        for t in targets {
            let frame = appkit_rect(t.frame, height);
            let level = placeholder_level(t.layer);
            let cover = match self.covers.get_mut(&t.id) {
                Some(c) => {
                    c.moving = if c.last == frame { c.moving.saturating_sub(1) } else { SETTLE_TICKS };
                    c.last = frame;
                    c
                }
                None => {
                    let window = self.spares.pop().unwrap_or_else(|| placeholder_window(mtm));
                    window.orderFrontRegardless();
                    self.covers.entry(t.id).or_insert(Cover { window, last: frame, moving: 0 })
                }
            };
            // A cover in motion holds a margin, so one tick of lag never uncovers an edge.
            let bleed = if cover.moving > 0 { -BLEED_WHILE_MOVING } else { 0.0 };
            place(&cover.window, inset(frame, bleed), level);
        }
        let live: HashSet<u32> = targets.iter().map(|t| t.id).collect();
        let gone: Vec<u32> = self.covers.keys().filter(|id| !live.contains(id)).copied().collect();
        for id in gone {
            let cover = self.covers.remove(&id).expect("listed above");
            self.retire(cover.window);
        }
    }

    pub fn clear(&mut self) {
        let covers: Vec<Cover> = self.covers.drain().map(|(_, c)| c).collect();
        for cover in covers {
            self.retire(cover.window);
        }
    }

    fn retire(&mut self, window: Retained<NSWindow>) {
        window.orderOut(None);
        if self.spares.len() < SPARES {
            self.spares.push(window);
        }
    }
}

fn placeholder_window(mtm: MainThreadMarker) -> Retained<NSWindow> {
    let window = overlay_window(mtm, placeholder_level(0));
    window.setBackgroundColor(Some(&NSColor::colorWithWhite_alpha(0.0, 0.995)));
    let image = NSImage::initWithData(NSImage::alloc(), &NSData::with_bytes(CAPTION)).expect("bundled caption decodes");
    image.setSize(CAPTION_SIZE);
    let view = NSImageView::imageViewWithImage(&image, mtm);
    view.setImageScaling(NSImageScaling::ScaleNone);
    window.setContentView(Some(&view));
    window
}

fn place(window: &NSWindow, frame: NSRect, level: isize) {
    if window.level() != level {
        window.setLevel(level);
    }
    if window.frame() != frame {
        window.setFrame_display(frame, false);
    }
    let fits = frame.size.width >= CAPTION_SIZE.width + 48.0 && frame.size.height >= CAPTION_SIZE.height + 96.0;
    if let Some(view) = window.contentView() {
        view.setHidden(!fits);
    }
}

fn inset(r: NSRect, d: f64) -> NSRect {
    NSRect::new(NSPoint::new(r.origin.x + d, r.origin.y + d), NSSize::new(r.size.width - 2.0 * d, r.size.height - 2.0 * d))
}
