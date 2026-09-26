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
    private static let captionMargin = CGSize(width: 48, height: 96)
    private static let creditFontSize: CGFloat = 26
    private let caption = NSStackView()
    private lazy var captionSize = caption.fittingSize

    init() {
        super.init(level: OverlayLevel.placeholder(coveringLayer: 0))
        backgroundColor = NSColor.black.withAlphaComponent(0.995)
        let content = NSView()
        content.wantsLayer = true
        caption.orientation = .vertical
        caption.alignment = .centerX
        caption.spacing = 20
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
        caption.isHidden = frame.width < captionSize.width + Self.captionMargin.width
            || frame.height < captionSize.height + Self.captionMargin.height
    }

    private static func headline() -> NSView {
        let label = NSTextField(labelWithString: "Nyx is protecting this window")
        label.font = Theme.nsFont(30)
        label.textColor = .white
        return label
    }

    /// Hand-laid rather than stacked: the wordmark has to sit on the label's
    /// baseline, and a stack view would only centre its box against the text.
    private static func credit() -> NSView {
        let row = NSView()
        let label = NSTextField(labelWithString: "Developed by")
        label.font = Theme.nsFont(creditFontSize)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            label.topAnchor.constraint(equalTo: row.topAnchor),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        guard let unravel = Theme.unravel else {
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
            return row
        }
        let mark = NSImageView(image: unravel)
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.setAccessibilityLabel("unravel")
        mark.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(mark)
        let height = Theme.wordmarkHeight(forFontSize: creditFontSize)
        NSLayoutConstraint.activate([
            mark.heightAnchor.constraint(equalToConstant: height),
            mark.widthAnchor.constraint(
                equalTo: mark.heightAnchor,
                multiplier: unravel.size.width / unravel.size.height
            ),
            mark.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            mark.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            mark.topAnchor.constraint(
                equalTo: label.lastBaselineAnchor,
                constant: -Theme.wordmarkBaseline(inHeight: height)
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
