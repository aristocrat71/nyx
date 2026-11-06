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
use objc2_quartz_core::{kCAGravityResize, CATransaction};
use objc2_screen_capture_kit::{
    SCContentFilter, SCDisplay, SCFrameStatus, SCShareableContent, SCStream, SCStreamConfiguration,
    SCStreamDelegate, SCStreamErrorCode, SCStreamErrorDomain, SCStreamFrameInfoStatus, SCStreamOutput,
    SCStreamOutputType,
};
use std::collections::HashMap;

// Mirror: what the user sees through the placeholders. One capture-excluded window per
// display, fed by a ScreenCaptureKit stream of every window the app owns, menus included.

#[derive(Default)]
pub struct Mirror;

impl Mirror {
    pub fn start(&mut self, _pid: i32) {}
    pub fn stop(&mut self) {}
    pub fn restack(&mut self, _targets: &[Target]) {}
}

fn configuration(mtm: MainThreadMarker, display: &SCDisplay) -> Retained<SCStreamConfiguration> {
    let id = unsafe { display.displayID() };
    let scale = NSScreen::screens(mtm)
        .iter()
        .find(|s| {
            let number = s.deviceDescription().objectForKey(&NSString::from_str("NSScreenNumber"));
            number.and_then(|n| n.downcast::<NSNumber>().ok()).is_some_and(|n| n.unsignedIntValue() == id)
        })
        .map_or(2.0, |s| s.backingScaleFactor());
    let config = unsafe { SCStreamConfiguration::new() };
    unsafe {
        config.setWidth(((display.width() as f64) * scale).max(1.0) as usize);
        config.setHeight(((display.height() as f64) * scale).max(1.0) as usize);
        config.setMinimumFrameInterval(CMTime::new(1, 60));
        config.setPixelFormat(kCVPixelFormatType_32BGRA);
        config.setShowsCursor(false);
        config.setQueueDepth(3);
    }
    config
}

/// Excluded from capture before it is ever ordered on screen, so no mirrored frame reaches a viewer.
fn mirror_window(mtm: MainThreadMarker, level: isize, frame: NSRect) -> Retained<NSWindow> {
    let window = overlay_window(mtm, level);
    window.setSharingType(NSWindowSharingType::None);
    let view = NSView::new(mtm);
    view.setWantsLayer(true);
    if let Some(layer) = view.layer() {
        layer.setContentsGravity(unsafe { kCAGravityResize });
    }
    window.setContentView(Some(&view));
    window.setFrame_display(frame, false);
    window.orderFrontRegardless();
    window
}

fn frame_complete(sample: &CMSampleBuffer) -> bool {
    let Some(attachments) = (unsafe { sample.sample_attachments_array(false) }) else { return false };
    let attachments: &NSArray<NSDictionary<NSString, AnyObject>> = unsafe { &*(&*attachments as *const _ as *const _) };
    let status = attachments.firstObject().and_then(|a| a.objectForKey(unsafe { SCStreamFrameInfoStatus }));
    status.and_then(|s| s.downcast::<NSNumber>().ok()).is_some_and(|s| s.integerValue() == SCFrameStatus::Complete.0)
}
