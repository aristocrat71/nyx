use super::{x, X};
use std::collections::{HashMap, HashSet};
use std::sync::OnceLock;
use x11rb::connection::Connection;
use x11rb::protocol::shape::{self, SK, SO};
use x11rb::protocol::xproto::{
    ChangeWindowAttributesAux, ClipOrdering, ConfigureWindowAux, ConnectionExt, CreateGCAux, CreateWindowAux,
    ImageFormat, MapState, Rectangle, StackMode, Window, WindowClass,
};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Target {
    pub id: Window,
    pub frame: Rectangle,
}

/// Top-level windows the process owns: the window manager's frames around its clients, and its
/// override-redirect popups. ponytail: walks the tree each tick; cache frame-to-pid if it shows in a profile.
pub fn windows_of(pid: i32) -> Vec<Target> {
    let Some(x) = x() else { return vec![] };
    let Some(tree) = x.conn.query_tree(x.root).ok().and_then(|c| c.reply().ok()) else { return vec![] };
    tree.children
        .into_iter()
        .filter(|w| owned_by(x, *w, pid as u32, 2))
        .filter_map(|w| {
            let attrs = x.conn.get_window_attributes(w).ok()?.reply().ok()?;
            (attrs.map_state == MapState::VIEWABLE).then_some(())?;
            let g = x.conn.get_geometry(w).ok()?.reply().ok()?;
            let border = g.border_width * 2;
            Some(Target { id: w, frame: Rectangle { x: g.x, y: g.y, width: g.width + border, height: g.height + border } })
        })
        .collect()
}

fn owned_by(x: &X, window: Window, pid: u32, depth: u8) -> bool {
    x.pid_of(window) == Some(pid)
        || depth > 0
            && x.conn.query_tree(window).ok().and_then(|c| c.reply().ok()).is_some_and(|t| t.children.iter().any(|c| owned_by(x, *c, pid, depth - 1)))
}

const BLEED_WHILE_MOVING: i16 = 24;
const SETTLE_TICKS: u8 = 6;
const SPARES: usize = 8;

struct Cover {
    window: Window,
    last: Rectangle,
    placed: Option<Rectangle>,
    moving: u8,
}

#[derive(Default)]
pub struct Placeholders {
    covers: HashMap<Window, Cover>,
    spares: Vec<Window>,
}

impl Placeholders {
    pub fn cover(&mut self, targets: &[Target]) {
        let Some(x) = x() else { return };
        for t in targets {
            let fresh = !self.covers.contains_key(&t.id);
            let Some(window) = (if fresh { self.spares.pop().or_else(|| placeholder_window(x)) } else { None }).or(self.covers.get(&t.id).map(|c| c.window)) else { continue };
            let cover = self.covers.entry(t.id).or_insert(Cover { window, last: t.frame, placed: None, moving: 0 });
            cover.moving = if fresh || cover.last == t.frame { cover.moving.saturating_sub(1) } else { SETTLE_TICKS };
            cover.last = t.frame;
            // A cover in motion holds a margin, so one tick of lag never uncovers an edge.
            let b = if cover.moving > 0 { BLEED_WHILE_MOVING } else { 0 };
            let f = t.frame;
            let want = Rectangle { x: f.x - b, y: f.y - b, width: f.width + 2 * b as u16, height: f.height + 2 * b as u16 };
            if cover.placed != Some(want) {
                place(x, cover.window, want, cover.placed);
                cover.placed = Some(want);
            }
        }
        let live: HashSet<Window> = targets.iter().map(|t| t.id).collect();
        let gone: Vec<Window> = self.covers.keys().filter(|id| !live.contains(id)).copied().collect();
        for id in gone {
            let cover = self.covers.remove(&id).expect("listed above");
            self.retire(cover.window);
        }
        let _ = x.conn.flush();
    }

    pub fn clear(&mut self) {
        let windows: Vec<Window> = self.covers.drain().map(|(_, c)| c.window).collect();
        windows.into_iter().for_each(|w| self.retire(w));
        if let Some(x) = x() {
            let _ = x.conn.flush();
        }
    }

    fn retire(&mut self, window: Window) {
        if let Some(x) = x() {
            let _ = x.conn.unmap_window(window);
        }
        if self.spares.len() < SPARES {
            self.spares.push(window);
        }
    }
}

/// Override-redirect, so the window manager never moves it, and an empty input shape, so clicks pass through.
fn placeholder_window(x: &X) -> Option<Window> {
    let id = x.conn.generate_id().ok()?;
    let aux = CreateWindowAux::new().background_pixel(0).override_redirect(1);
    x.conn.create_window(x.depth, id, x.root, 0, 0, 1, 1, 0, WindowClass::INPUT_OUTPUT, 0, &aux).ok()?;
    shape::rectangles(&x.conn, SO::SET, SK::INPUT, ClipOrdering::UNSORTED, id, 0, 0, &[]).ok()?;
    Some(id)
}

/// Raised only when first mapped; the caption is repainted into the background only when the size changes.
fn place(x: &X, window: Window, r: Rectangle, before: Option<Rectangle>) {
    let mut aux = ConfigureWindowAux::new().x(r.x as i32).y(r.y as i32).width(r.width as u32).height(r.height as u32);
    if before.is_none() {
        aux = aux.stack_mode(StackMode::ABOVE);
    }
    let _ = x.conn.configure_window(window, &aux);
    if before.is_none_or(|b| (b.width, b.height) != (r.width, r.height)) {
        paint(x, window, r.width, r.height);
    }
    if before.is_none() {
        let _ = x.conn.map_window(window);
    }
}

/// The @2x caption PNG, halved to 522x169 and composited onto black, as the server's BGRX.
fn caption() -> &'static (Vec<u8>, u16, u16) {
    static CAPTION: OnceLock<(Vec<u8>, u16, u16)> = OnceLock::new();
    CAPTION.get_or_init(|| {
        let image = tauri::image::Image::from_bytes(include_bytes!("../../../assets/caption.png")).expect("caption decodes");
        let (w, h, src) = (image.width() as usize, image.height() as usize, image.rgba());
        let mut out = Vec::with_capacity(w * h);
        for y in (0..h - 1).step_by(2) {
            for x in (0..w - 1).step_by(2) {
                let px = |dx: usize, dy: usize, c: usize| {
                    let p = &src[((y + dy) * w + x + dx) * 4..][..4];
                    p[c] as u32 * p[3] as u32 / 255
                };
                let avg = |c: usize| ((px(0, 0, c) + px(1, 0, c) + px(0, 1, c) + px(1, 1, c)) / 4) as u8;
                out.extend([avg(2), avg(1), avg(0), 0]);
            }
        }
        (out, (w / 2) as u16, (h / 2) as u16)
    })
}

fn paint(x: &X, window: Window, width: u16, height: u16) {
    let (Ok(pixmap), Ok(gc)) = (x.conn.generate_id(), x.conn.generate_id()) else { return };
    let _ = x.conn.create_pixmap(x.depth, pixmap, window, width.max(1), height.max(1));
    let _ = x.conn.create_gc(gc, pixmap, &CreateGCAux::new().foreground(0));
    let _ = x.conn.poly_fill_rectangle(pixmap, gc, &[Rectangle { x: 0, y: 0, width, height }]);
    let (pixels, cw, ch) = caption();
    if width >= cw + 48 && height >= ch + 96 {
        let (dx, dy) = (((width - cw) / 2) as i16, ((height - ch) / 2) as i16);
        let _ = x.conn.put_image(ImageFormat::Z_PIXMAP, pixmap, gc, *cw, *ch, dx, dy, 0, x.depth, pixels);
    }
    let _ = x.conn.change_window_attributes(window, &ChangeWindowAttributesAux::new().background_pixmap(pixmap));
    let _ = x.conn.clear_area(false, window, 0, 0, 0, 0);
    let _ = x.conn.free_gc(gc);
    let _ = x.conn.free_pixmap(pixmap);
}
