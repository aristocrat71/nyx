import AppKit
import SwiftUI

/// Windows AppKit creates on Nyx's behalf — popovers, menus — do not inherit
/// the dashboard's `sharingType` and default to `.readOnly`, so viewers would
/// see the app picker and the protection state. Both are excluded before they
/// are first displayed.
@MainActor
enum CaptureExclusion {
    /// Call from `menuNeedsUpdate`/`menuWillOpen`: the menu's window already
    /// exists there but is not yet visible.
    static func excludeMenuWindows() {
        for window in NSApp.windows
        where window.sharingType != .none
            && String(describing: type(of: window)).contains("MenuWindow") {
            window.sharingType = .none
        }
    }
}

struct CaptureExcluded: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ExcludingView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.sharingType = .none
    }

    private final class ExcludingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.sharingType = .none
        }
    }
}
