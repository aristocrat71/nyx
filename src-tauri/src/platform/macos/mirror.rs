use super::has_screen_permission;
use super::overlay::{appkit_rect, mirror_level, overlay_window, primary_height, Target};
use crate::engine::{self, MirrorEvent};
use block2::RcBlock;
use dispatch2::DispatchQueue;
use objc2::rc::Retained;
use objc2::runtime::{AnyObject, NSObject, NSObjectProtocol, ProtocolObject};
use objc2::{define_class, msg_send, AllocAnyThread, DefinedClass, MainThreadMarker};
use objc2_app_kit::{NSScreen, NSView, NSWindow, NSWindowSharingType};
use objc2_core_foundation::CFRetained;
use objc2_core_media::{CMSampleBuffer, CMTime};
use objc2_core_video::{kCVPixelFormatType_32BGRA, CVPixelBuffer, CVPixelBufferGetIOSurface};
use objc2_foundation::{NSArray, NSDictionary, NSError, NSNumber, NSRect, NSString};
use objc2_quartz_core::{kCAGravityResize, CALayer, CATransaction};
use objc2_screen_capture_kit::{
    SCContentFilter, SCDisplay, SCFrameStatus, SCShareableContent, SCStream, SCStreamConfiguration,
    SCStreamDelegate, SCStreamErrorCode, SCStreamErrorDomain, SCStreamFrameInfoStatus, SCStreamOutput,
    SCStreamOutputType,
};
use std::collections::HashMap;
use std::cell::RefCell;
use std::sync::atomic::{AtomicBool, Ordering};

// Mirror: what the user sees through the placeholders. One capture-excluded window per
// display, fed by a ScreenCaptureKit stream of every window the app owns, menus included.

/// SCK and CoreVideo objects are immutable once handed over, so hopping one to the main thread is safe.
struct Handoff<T>(T);
unsafe impl<T> Send for Handoff<T> {}

impl<T> Handoff<T> {
    fn take(self) -> T {
        self.0
    }
}

#[derive(Default)]
pub struct Mirror {
    epoch: u64,
    level: isize,
    streams: Vec<(Retained<SCStream>, Retained<StreamOutput>)>,
    windows: HashMap<u32, Retained<NSWindow>>,
}

fn post_event(epoch: u64, event: MirrorEvent) {
    engine::post(move |nyx| {
        if nyx.mirror.epoch == epoch {
            nyx.mirror_event(event);
        }
    });
}

impl Mirror {
    pub fn start(&mut self, pid: i32) {
        self.stop();
        let epoch = self.epoch;
        if !has_screen_permission() {
            return post_event(epoch, MirrorEvent::NoPermission);
        }
        let block = RcBlock::new(move |content: *mut SCShareableContent, error: *mut NSError| {
            let content = unsafe { Retained::retain(content) }.filter(|_| error.is_null()).map(Handoff);
            engine::post(move |nyx| {
                if nyx.mirror.epoch != epoch {
                    return;
                }
                let begun = content.is_some_and(|c| nyx.mirror.begin(pid, &c.take()));
                if !begun {
                    nyx.mirror_event(MirrorEvent::Failed);
                }
            });
        });
        unsafe {
            SCShareableContent::getShareableContentExcludingDesktopWindows_onScreenWindowsOnly_completionHandler(
                false, true, &block,
            )
        };
    }

    pub fn stop(&mut self) {
        self.epoch += 1;
        for (stream, _) in self.streams.drain(..) {
            unsafe { stream.stopCaptureWithCompletionHandler(None) };
        }
        for window in self.windows.drain().map(|(_, w)| w) {
            window.orderOut(None);
        }
    }

    /// Assigning a level re-orders the windows, so it only happens on a change.
    pub fn restack(&mut self, targets: &[Target]) {
        let level = mirror_level(targets);
        if level != self.level {
            self.level = level;
            self.windows.values().for_each(|w| w.setLevel(level));
        }
    }

    /// A protected app with no shareable windows yet is normal right after launch; the retry picks it up.
    fn begin(&mut self, pid: i32, content: &SCShareableContent) -> bool {
        let mtm = MainThreadMarker::new().expect("mirror lives on the main thread");
        let Some(height) = primary_height(mtm) else { return false };
        let apps = unsafe { content.applications() };
        let Some(app) = apps.iter().find(|a| unsafe { a.processID() } == pid) else { return false };
        let apps = NSArray::from_retained_slice(&[app]);
        let queue = DispatchQueue::new("nyx.mirror.frames", None);
        for display in unsafe { content.displays() } {
            let id = unsafe { display.displayID() };
            let filter = unsafe {
                SCContentFilter::initWithDisplay_includingApplications_exceptingWindows(
                    SCContentFilter::alloc(), &display, &apps, &NSArray::new(),
                )
            };
            unsafe { filter.setIncludeMenuBar(false) };
            let (window, layer) = mirror_window(mtm, self.level, appkit_rect(unsafe { display.frame() }, height));
            let output = StreamOutput::new(self.epoch, layer);
            let delegate = ProtocolObject::from_ref(&*output);
            let stream = unsafe {
                SCStream::initWithFilter_configuration_delegate(
                    SCStream::alloc(), &filter, &configuration(mtm, id, &display), Some(delegate),
                )
            };
            let added = unsafe {
                stream.addStreamOutput_type_sampleHandlerQueue_error(
                    ProtocolObject::from_ref(&*output), SCStreamOutputType::Screen, Some(&queue),
                )
            };
            if let Err(e) = added {
                log::error!("addStreamOutput failed: {}", e.localizedDescription());
                continue;
            }
            self.windows.insert(id, window);
            let epoch = self.epoch;
            let started = RcBlock::new(move |error: *mut NSError| {
                if !error.is_null() {
                    log::error!("startCapture failed");
                    post_event(epoch, MirrorEvent::Failed);
                }
            });
            unsafe { stream.startCaptureWithCompletionHandler(Some(&started)) };
            self.streams.push((stream, output));
        }
        !self.streams.is_empty()
    }
}

fn configuration(mtm: MainThreadMarker, id: u32, display: &SCDisplay) -> Retained<SCStreamConfiguration> {
    let screen = NSScreen::screens(mtm).iter().find(|s| {
        let number = s.deviceDescription().objectForKey(&NSString::from_str("NSScreenNumber"));
        number.and_then(|n| n.downcast::<NSNumber>().ok()).is_some_and(|n| n.unsignedIntValue() == id)
    });
    let scale = screen.as_ref().map_or(2.0, |s| s.backingScaleFactor());
    // At the display's own rate, so a 120 Hz screen is not mirrored at half speed.
    let fps = screen.as_ref().map_or(60, |s| s.maximumFramesPerSecond()).max(60);
    let config = unsafe { SCStreamConfiguration::new() };
    unsafe {
        config.setWidth(((display.width() as f64) * scale).max(1.0) as usize);
        config.setHeight(((display.height() as f64) * scale).max(1.0) as usize);
        config.setMinimumFrameInterval(CMTime::new(1, fps as i32));
        config.setPixelFormat(kCVPixelFormatType_32BGRA);
        config.setShowsCursor(false);
        config.setQueueDepth(3);
    }
    config
}

/// Excluded from capture before it is ever ordered on screen, so no mirrored frame reaches a viewer.
/// The view hosts its own layer, so frames can be set on it from the capture queue.
fn mirror_window(mtm: MainThreadMarker, level: isize, frame: NSRect) -> (Retained<NSWindow>, Retained<CALayer>) {
    let window = overlay_window(mtm, level);
    window.setSharingType(NSWindowSharingType::None);
    let layer = CALayer::new();
    layer.setContentsGravity(unsafe { kCAGravityResize });
    let view = NSView::new(mtm);
    view.setLayer(Some(&layer));
    view.setWantsLayer(true);
    window.setContentView(Some(&view));
    window.setFrame_display(frame, false);
    window.orderFrontRegardless();
    (window, layer)
}

struct StreamIvars {
    epoch: u64,
    layer: Retained<CALayer>,
    /// The parent buffer, not just its surface: SCK's pool rewrites the surface underneath otherwise.
    held: RefCell<Option<CFRetained<CVPixelBuffer>>>,
    running: AtomicBool,
}

define_class!(
    #[unsafe(super(NSObject))]
    #[name = "NyxStreamOutput"]
    #[ivars = StreamIvars]
    struct StreamOutput;

    unsafe impl NSObjectProtocol for StreamOutput {}

    unsafe impl SCStreamOutput for StreamOutput {
        #[unsafe(method(stream:didOutputSampleBuffer:ofType:))]
        fn did_output(&self, _stream: &SCStream, sample: &CMSampleBuffer, kind: SCStreamOutputType) {
            if kind != SCStreamOutputType::Screen || !frame_complete(sample) {
                return;
            }
            let Some(buffer) = (unsafe { sample.image_buffer() }) else { return };
            // Shown right here on the capture queue: a hop to the main thread waits behind the resnap.
            let Some(surface) = CVPixelBufferGetIOSurface(Some(&buffer)) else { return };
            CATransaction::begin();
            CATransaction::setDisableActions(true);
            unsafe { self.ivars().layer.setContents(Some(&*(CFRetained::as_ptr(&surface).as_ptr() as *const AnyObject))) };
            CATransaction::commit();
            self.ivars().held.replace(Some(buffer));
            if !self.ivars().running.swap(true, Ordering::Relaxed) {
                post_event(self.ivars().epoch, MirrorEvent::Running);
            }
        }
    }

    unsafe impl SCStreamDelegate for StreamOutput {
        #[unsafe(method(stream:didStopWithError:))]
        fn did_stop(&self, _stream: &SCStream, error: &NSError) {
            let user = error.code() == SCStreamErrorCode::UserStopped.0 && &*error.domain() == unsafe { SCStreamErrorDomain };
            log::error!("stream stopped: {}", error.localizedDescription());
            post_event(self.ivars().epoch, if user { MirrorEvent::UserStopped } else { MirrorEvent::Failed });
        }
    }
);

impl StreamOutput {
    fn new(epoch: u64, layer: Retained<CALayer>) -> Retained<Self> {
        let this = Self::alloc().set_ivars(StreamIvars { epoch, layer, held: RefCell::default(), running: AtomicBool::new(false) });
        unsafe { msg_send![super(this), init] }
    }
}

fn frame_complete(sample: &CMSampleBuffer) -> bool {
    let Some(attachments) = (unsafe { sample.sample_attachments_array(false) }) else { return false };
    let attachments: &NSArray<NSDictionary<NSString, AnyObject>> = unsafe { &*(&*attachments as *const _ as *const _) };
    let status = attachments.firstObject().and_then(|a| a.objectForKey(unsafe { SCStreamFrameInfoStatus }));
    status.and_then(|s| s.downcast::<NSNumber>().ok()).is_some_and(|s| s.integerValue() == SCFrameStatus::Complete.0)
}
