import SwiftUI

enum Theme {
    static let background = Color(nsColor: NSColor(hex: 0x0E0F12))
    static let panel = Color(nsColor: NSColor(hex: 0x16181D))
    static let text = Color(nsColor: NSColor(hex: 0xE8E8E8))
    static let muted = Color(nsColor: NSColor(hex: 0x8A8F98))
    static let amber = Color(nsColor: NSColor(hex: 0xF5A623))
    static let danger = Color(nsColor: NSColor(hex: 0xE5534B))

    static let backgroundNS = NSColor(hex: 0x0E0F12)
    static let panelNS = NSColor(hex: 0x16181D)
    static let amberNS = NSColor(hex: 0xF5A623)

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
}
