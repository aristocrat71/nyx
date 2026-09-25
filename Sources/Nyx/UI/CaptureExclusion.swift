import AppKit
import SwiftUI

/// Popovers and menus AppKit makes on Nyx's behalf default to `.readOnly` instead
/// of inheriting the dashboard's `sharingType`, so each is excluded before it shows.
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
