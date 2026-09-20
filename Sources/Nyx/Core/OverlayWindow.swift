import AppKit

enum OverlayLevel {
    /// Nothing Nyx puts on screen may reach the screen saver: protected content
    /// must never be composited over a locked screen.
    private static let ceiling = Int(CGWindowLevelForKey(.screenSaverWindow)) - 1

    /// One level above the covered window and no higher: the levels over an
    /// ordinary window hold the Dock, the switcher and the menu bar.
    static func placeholder(coveringLayer layer: Int) -> NSWindow.Level {
        NSWindow.Level(rawValue: min(layer, ceiling - 2) + 1)
    }

    /// One step above the tallest placeholder, so the preview lands on the black
    /// cover and nowhere higher.
    static func mirror(coveringLayers layers: [Int]) -> NSWindow.Level {
        let top = layers.lazy.map { placeholder(coveringLayer: $0).rawValue }.max()
            ?? placeholder(coveringLayer: 0).rawValue
        return NSWindow.Level(rawValue: min(top + 1, ceiling))
    }
}

/// Non-opaque so macOS never reports the covered window as occluded —
/// Electron/Chromium apps stop rendering (frozen mirror) when occluded.
class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(level: NSWindow.Level) {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }
}

final class PlaceholderWindow: OverlayWindow {
    private static let minimumLabelSize = CGSize(width: 320, height: 160)
    private static let creditMarkHeight: CGFloat = 15
    private let caption = NSStackView()

    init() {
        super.init(level: OverlayLevel.placeholder(coveringLayer: 0))
        backgroundColor = NSColor.black.withAlphaComponent(0.995)
        let content = NSView()
        content.wantsLayer = true
        caption.orientation = .vertical
        caption.alignment = .centerX
        caption.spacing = 18
        caption.setViews([Self.headline(), Self.credit()], in: .center)
        caption.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(caption)
        NSLayoutConstraint.activate([
            caption.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            caption.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    func place(at frame: CGRect, level: NSWindow.Level) {
        if self.level != level { self.level = level }
        if self.frame != frame { setFrame(frame, display: false) }
        caption.isHidden = frame.width < Self.minimumLabelSize.width
            || frame.height < Self.minimumLabelSize.height
    }

    private static func headline() -> NSView {
        let label = NSTextField(labelWithString: "Nyx is protecting this window")
        label.font = Theme.nsFont(22)
        label.textColor = .white
        return label
    }

    private static func credit() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        let label = NSTextField(labelWithString: "Developed by")
        label.font = Theme.nsFont(13)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        row.addArrangedSubview(label)
        guard let unravel = Theme.unravel else { return row }
        let mark = NSImageView(image: unravel)
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.setAccessibilityLabel("unravel")
        row.addArrangedSubview(mark)
        NSLayoutConstraint.activate([
            mark.heightAnchor.constraint(equalToConstant: creditMarkHeight),
            mark.widthAnchor.constraint(
                equalTo: mark.heightAnchor,
                multiplier: unravel.size.width / unravel.size.height
            ),
        ])
        return row
    }
}

final class MirrorWindow: OverlayWindow {
    override init(level: NSWindow.Level) {
        super.init(level: level)
        // Set before the window is ever ordered on screen, so no frame of the
        // mirrored content can reach a viewer.
        sharingType = .none
        let content = NSView()
        content.wantsLayer = true
        content.layer?.contentsGravity = .resize
        contentView = content
    }

    func show(covering frame: CGRect) {
        setFrame(frame, display: false)
        orderFront(nil)
    }

    func present(_ surface: IOSurfaceRef) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentView?.layer?.contents = surface
        CATransaction.commit()
    }
}
