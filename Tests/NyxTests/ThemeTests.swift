import AppKit
import CoreText
import Testing
@testable import Nyx

@Suite("Bundled assets")
@MainActor
struct BundledAssetTests {
    /// A resource that fails to reach the bundle leaves the header with no
    /// logo and nothing else to show for it.
    @Test func theOwlArtworkLoadsAsATemplate() throws {
        let owl = try #require(Theme.owl)
        #expect(owl.isTemplate)
        #expect(owl.size.width > 0 && owl.size.height > 0)
    }

    /// A wordmark that misses the bundle is dropped silently by every caller,
    /// so the credit line would read "made with love by" and stop there.
    @Test func theUnravelWordmarkLoadsInItsOwnColours() throws {
        let unravel = try #require(Theme.unravel)
        #expect(!unravel.isTemplate)
        #expect(unravel.size.width > unravel.size.height)
    }

    /// Keyed off the paper it was drawn on: if the background survived, the
    /// corners would be opaque and the logo would be a box on a dark dashboard.
    @Test func theArtworkBackgroundIsTransparent() throws {
        let owl = try #require(Theme.owl)
        let data = try #require(owl.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        for x in [0, rep.pixelsWide - 1] {
            for y in [0, rep.pixelsHigh - 1] {
                #expect(try #require(rep.colorAt(x: x, y: y)).alphaComponent == 0)
            }
        }
    }
}

@Suite("Bundled font coverage")
@MainActor
struct FontCoverageTests {
    /// A glyph JetBrains Mono lacks renders as nothing at all, which is how a
    /// button labelled ☀ ended up invisible rather than merely ugly.
    @Test(arguments: ["⌃⇧L", "✕", "+ Add app…", "Light", "Dark", "PROTECTED APPS", "Nyx"])
    func everyLabelTheDashboardDrawsHasGlyphs(label: String) {
        Theme.registerBundledFonts()
        let font = Theme.nsFont(12)
        var utf16 = Array(label.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        #expect(CTFontGetGlyphsForCharacters(font, &utf16, &glyphs, utf16.count))
    }
}

@Suite("Theme appearances")
@MainActor
struct ThemeTests {
    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func resolve(_ color: NSColor, in name: NSAppearance.Name) throws -> NSColor {
        var resolved: NSColor?
        try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return try #require(resolved)
    }

    /// WCAG relative luminance, so the palette's legibility is asserted rather
    /// than eyeballed once and left to rot.
    private func luminance(_ color: NSColor) -> CGFloat {
        func channel(_ raw: CGFloat) -> CGFloat {
            raw <= 0.04045 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.redComponent)
            + 0.7152 * channel(color.greenComponent)
            + 0.0722 * channel(color.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Surfaces and inks have to move in opposite directions, which is the bug
    /// a provider wired up backwards would produce.
    @Test func theDashboardPaletteFollowsTheAppearance() throws {
        for surface in [Theme.backgroundNS, Theme.panelNS] {
            let light = try resolve(surface, in: .aqua)
            let dark = try resolve(surface, in: .darkAqua)
            #expect(luminance(light) > luminance(dark))
        }
        for ink in [Theme.textNS, Theme.mutedNS] {
            let light = try resolve(ink, in: .aqua)
            let dark = try resolve(ink, in: .darkAqua)
            #expect(luminance(light) < luminance(dark))
        }
    }

    /// AA for body text in both appearances. Light mode is the tight one: a
    /// dimmed grey that reads fine on near-black washes out on near-white.
    @Test func bodyTextClearsAAAgainstItsBackground() throws {
        for name in Self.appearances {
            let background = try resolve(Theme.backgroundNS, in: name)
            for ink in [Theme.textNS, Theme.mutedNS] {
                #expect(contrast(try resolve(ink, in: name), background) >= 4.5)
            }
            let panel = try resolve(Theme.panelNS, in: name)
            #expect(contrast(try resolve(Theme.textNS, in: name), panel) >= 4.5)
        }
    }

    @Test func statusDotsStayVisibleOnBothBackgrounds() throws {
        for name in Self.appearances {
            let background = try resolve(Theme.backgroundNS, in: name)
            for dot in [Theme.amberTextNS, Theme.dangerNS] {
                #expect(contrast(try resolve(dot, in: name), background) >= 3)
            }
        }
    }

    /// The amber fill is one colour in both appearances, so the label on it has
    /// to be readable without following the appearance either.
    @Test func theBannerButtonLabelReadsOnAmber() {
        #expect(contrast(Theme.inkOnAmberNS, Theme.amberNS) >= 4.5)
    }
}
