import AppKit

struct TargetWindow: Equatable {
    let id: CGWindowID
    let layer: Int
    let cgFrame: CGRect
}

enum WindowIndex {
    /// Every on-screen window owned by `pid`, at every layer. Context menus,
    /// File-menu dropdowns and tooltips are owned by the app that opened them
    /// and composite far above its ordinary windows, so they need covering too.
    static func onScreenWindows(of pid: pid_t) -> [TargetWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid else { return nil }
            return target(from: info)
        }
    }

    static func target(from info: [String: Any]) -> TargetWindow? {
        guard let id = info[kCGWindowNumber as String] as? CGWindowID,
              let layer = info[kCGWindowLayer as String] as? Int,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              frame.width >= 1, frame.height >= 1,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
        else { return nil }
        return TargetWindow(id: id, layer: layer, cgFrame: frame)
    }

    /// CGWindowList is top-left-origin; AppKit is bottom-left of the screen
    /// that carries the menu bar, which is always `NSScreen.screens.first`.
    static func appKitRect(fromCG cg: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    /// nil while AppKit reports no usable screen. Callers keep their last known
    /// geometry rather than repositioning a placeholder against a zero height.
    static var primaryScreenHeight: CGFloat? {
        guard let height = NSScreen.screens.first?.frame.height, height > 0 else { return nil }
        return height
    }

    static func backingScale(of displayID: CGDirectDisplayID) -> CGFloat {
        let screen = NSScreen.screens.first {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
        }
        return screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }
}
