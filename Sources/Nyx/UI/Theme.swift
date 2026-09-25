import CoreText
import SwiftUI

enum Theme {
    static func registerBundledFonts() {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts"),
              !urls.isEmpty else {
            Log.ui.error("no bundled fonts found, using system monospaced")
            return
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                Log.ui.error("font registration failed for \(url.lastPathComponent, privacy: .public)")
            }
        }
    }

    static let backgroundNS = NSColor.themed(light: 0xF6F6F7, dark: 0x0E0F12)
    static let panelNS = NSColor.themed(light: 0xFFFFFF, dark: 0x16181D)
    static let textNS = NSColor.themed(light: 0x1A1C20, dark: 0xE8E8E8)
    static let mutedNS = NSColor.themed(light: 0x6B7078, dark: 0x8A8F98)
    static let hairlineNS = NSColor.themed(light: 0x000000, dark: 0xFFFFFF, alpha: 0.09)
    static let rowHighlightNS = NSColor.themed(light: 0x000000, dark: 0xFFFFFF, alpha: 0.05)
    static let controlNS = NSColor.themed(light: 0x000000, dark: 0xFFFFFF, alpha: 0.07)
    static let selectionNS = NSColor.themed(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.16)
    static let controlBorderNS = NSColor.themed(light: 0x000000, dark: 0xFFFFFF, alpha: 0.18)
    /// The tray dot and the banner fill keep one amber across both appearances;
    /// amber *text* needs the darker tone to stay legible on a light banner.
    static let amberNS = NSColor(hex: 0xF5A623)
    static let amberTextNS = NSColor.themed(light: 0x8A5B06, dark: 0xF5A623)
    static let dangerNS = NSColor.themed(light: 0xB3352E, dark: 0xE5534B)
    /// Sits on the amber fill in both appearances, so it follows neither.
    static let inkOnAmberNS = NSColor(hex: 0x1A1206)

    static let background = Color(nsColor: backgroundNS)
    static let panel = Color(nsColor: panelNS)
    static let text = Color(nsColor: textNS)
    static let muted = Color(nsColor: mutedNS)
    static let amber = Color(nsColor: amberNS)
    static let amberText = Color(nsColor: amberTextNS)
    static let danger = Color(nsColor: dangerNS)
    static let hairline = Color(nsColor: hairlineNS)
    static let rowHighlight = Color(nsColor: rowHighlightNS)
    static let control = Color(nsColor: controlNS)
    static let selection = Color(nsColor: selectionNS)
    static let controlBorder = Color(nsColor: controlBorderNS)
    static let inkOnAmber = Color(nsColor: inkOnAmberNS)

    /// Drawn as a template: the artwork is one ink on paper, so keying the paper
    /// out leaves a mask the dashboard can tint for either appearance.
    static let owl: NSImage? = {
        guard let url = Bundle.module.url(forResource: "owl", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            Log.ui.error("bundled owl artwork missing")
            return nil
        }
        image.isTemplate = true
        return image
    }()

    /// Kept in its own colours, unlike the owl: it is someone else's wordmark,
    /// not a glyph for this window to tint.
    static let unravel: NSImage? = {
        guard let url = Bundle.module.url(forResource: "unravel", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            Log.ui.error("bundled unravel wordmark missing")
            return nil
        }
        return image
    }()

    /// The wordmark art pads its ink: the baseline sits 240 rows down of 260 and
    /// the x-height tops out at row 84, so type can be squared to both.
    private static let wordmarkBaselineFraction: CGFloat = 240 / 260
    private static let wordmarkXHeightFraction: CGFloat = (240 - 84) / 260

    /// Drawn this tall, the wordmark carries the x-height of `size` type beside it.
    static func wordmarkHeight(forFontSize size: CGFloat) -> CGFloat {
        nsFont(size).xHeight / wordmarkXHeightFraction
    }

    /// How far under the drawn wordmark's top edge its own baseline falls.
    static func wordmarkBaseline(inHeight height: CGFloat) -> CGFloat {
        height * wordmarkBaselineFraction
    }

    static func nsFont(_ size: CGFloat, medium: Bool = false) -> NSFont {
        let name = medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular"
        return NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: medium ? .medium : .regular)
    }

    static func font(_ size: CGFloat, medium: Bool = false) -> Font {
        Font(nsFont(size, medium: medium))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Resolved per appearance rather than at launch, so the dashboard follows
    /// the system between light and dark without being rebuilt.
    static func themed(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex).withAlphaComponent(alpha)
        }
    }
}
