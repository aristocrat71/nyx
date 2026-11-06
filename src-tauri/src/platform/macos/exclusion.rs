use objc2::rc::Retained;
use objc2::runtime::{NSObject, NSObjectProtocol, ProtocolObject};
use objc2::{define_class, msg_send, MainThreadMarker, MainThreadOnly};
use objc2_app_kit::{NSApplication, NSMenu, NSMenuDelegate, NSWindow, NSWindowSharingType};

// Viewers must never see Nyx's own UI: the list of protected apps is itself private.

pub fn exclude_window(window: &tauri::WebviewWindow) {
    if let Ok(ptr) = window.ns_window() {
        let window: &NSWindow = unsafe { &*(ptr as *const NSWindow) };
        window.setSharingType(NSWindowSharingType::None);
    }
}

/// Menus AppKit makes on Nyx's behalf default to readable instead of inheriting anything,
/// so the tray menu's windows are excluded in `menuNeedsUpdate`, before they first show.
pub fn exclude_tray_menu(tray: &tauri::tray::TrayIcon) {
    let _ = tray.with_inner_tray_icon(|inner| {
        let mtm = MainThreadMarker::new().expect("tray callbacks run on the main thread");
        let Some(menu) = inner.ns_status_item().and_then(|item| item.menu(mtm)) else { return };
        let delegate: Retained<MenuExcluder> = unsafe { msg_send![MenuExcluder::alloc(mtm), init] };
        menu.setDelegate(Some(ProtocolObject::from_ref(&*delegate)));
        // NSMenu holds its delegate weakly, and this one lives as long as the process.
        std::mem::forget(delegate);
    });
}

define_class!(
    #[unsafe(super(NSObject))]
    #[name = "NyxMenuExcluder"]
    #[thread_kind = MainThreadOnly]
    struct MenuExcluder;

    unsafe impl NSObjectProtocol for MenuExcluder {}

    unsafe impl NSMenuDelegate for MenuExcluder {
        #[unsafe(method(menuNeedsUpdate:))]
        fn menu_needs_update(&self, _menu: &NSMenu) {
            let app = NSApplication::sharedApplication(self.mtm());
            for window in app.windows() {
                let menu_window = window.class().name().to_string_lossy().contains("MenuWindow");
                if menu_window && window.sharingType() != NSWindowSharingType::None {
                    window.setSharingType(NSWindowSharingType::None);
                }
            }
        }
    }
);
