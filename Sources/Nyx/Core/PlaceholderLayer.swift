import AppKit

/// The black rectangles viewers see. Driven straight off CGWindowList, with no
/// dependency on ScreenCaptureKit, so cover goes up whether or not the mirror
/// can run — a failing capture degrades to "hidden", never to "visible".
@MainActor
final class PlaceholderLayer {
    /// Margin held while a window is in motion. One resnap tick of lag at a
    /// fast drag is worth a few points; a static window gets an exact fit.
    private static let bleedWhileMoving: CGFloat = 24
    private static let settleTicks = 6
    private static let spareLimit = 8

    private struct Cover {
        let window: PlaceholderWindow
        var lastFrame: CGRect
        var movingTicks: Int
    }

    private var covers: [CGWindowID: Cover] = [:]
    private var spares: [PlaceholderWindow] = []

    var isCovering: Bool { !covers.isEmpty }

    func cover(_ targets: [TargetWindow]) {
        guard let primaryHeight = WindowIndex.primaryScreenHeight else { return }
        var live = Set<CGWindowID>(minimumCapacity: targets.count)

        for target in targets {
            live.insert(target.id)
            let frame = WindowIndex.appKitRect(fromCG: target.cgFrame, primaryHeight: primaryHeight)
            let level = OverlayLevel.placeholder(coveringLayer: target.layer)

            if var cover = covers[target.id] {
                cover.movingTicks = cover.lastFrame == frame
                    ? max(0, cover.movingTicks - 1)
                    : Self.settleTicks
                cover.lastFrame = frame
                covers[target.id] = cover
                cover.window.place(at: Self.bleed(frame, moving: cover.movingTicks > 0), level: level)
            } else {
                let window = spares.popLast() ?? PlaceholderWindow()
                window.place(at: frame, level: level)
                window.orderFront(nil)
                covers[target.id] = Cover(window: window, lastFrame: frame, movingTicks: 0)
            }
        }

        for (id, cover) in covers where !live.contains(id) {
            retire(cover.window)
            covers[id] = nil
        }
    }

    func clear() {
        for cover in covers.values { retire(cover.window) }
        covers.removeAll()
    }

    private func retire(_ window: PlaceholderWindow) {
        window.orderOut(nil)
        if spares.count < Self.spareLimit { spares.append(window) }
    }

    private static func bleed(_ frame: CGRect, moving: Bool) -> CGRect {
        guard moving else { return frame }
        return frame.insetBy(dx: -bleedWhileMoving, dy: -bleedWhileMoving)
    }
}
