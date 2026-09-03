import AppKit
import Testing
@testable import Nyx

@Suite("CG to AppKit geometry")
struct GeometryTests {
    private let primaryHeight: CGFloat = 1000

    @Test func windowOnPrimaryDisplayFlipsAboutThePrimaryHeight() {
        let cg = CGRect(x: 100, y: 200, width: 400, height: 300)
        #expect(WindowIndex.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
            == CGRect(x: 100, y: 500, width: 400, height: 300))
    }

    @Test func windowFlushWithTheTopOfThePrimaryDisplay() {
        let cg = CGRect(x: 0, y: 0, width: 200, height: 100)
        #expect(WindowIndex.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
            == CGRect(x: 0, y: 900, width: 200, height: 100))
    }

    /// A display above the primary has negative CG y, which must map to an
    /// AppKit y above the primary's top edge, not to a clamped or negative one.
    @Test func displayAboveThePrimaryMapsAboveIt() {
        let cg = CGRect(x: 0, y: -800, width: 1600, height: 600)
        let appKit = WindowIndex.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        #expect(appKit == CGRect(x: 0, y: 1200, width: 1600, height: 600))
        #expect(appKit.minY > primaryHeight)
    }

    @Test func displayLeftOfThePrimaryKeepsItsNegativeX() {
        let cg = CGRect(x: -1920, y: 100, width: 500, height: 400)
        #expect(WindowIndex.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
            == CGRect(x: -1920, y: 500, width: 500, height: 400))
    }

    /// A display hanging below the primary produces a negative AppKit y —
    /// correct, and the value the placeholder must be given.
    @Test func displayBelowThePrimaryProducesNegativeY() {
        let cg = CGRect(x: 0, y: 1000, width: 1920, height: 1080)
        #expect(WindowIndex.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
            == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    @Test func conversionIsItsOwnInverse() {
        let cg = CGRect(x: -400, y: -250, width: 800, height: 600)
        let appKit = WindowIndex.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        let back = WindowIndex.appKitRect(fromCG: appKit, primaryHeight: primaryHeight)
        #expect(back == cg)
    }
}

@Suite("Window enumeration")
struct WindowIndexTests {
    private var wellFormed: [String: Any] {
        [
            kCGWindowNumber as String: CGWindowID(42),
            kCGWindowLayer as String: 0,
            kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 300, "Height": 200],
        ]
    }

    @Test func aWellFormedEntryParses() throws {
        let target = try #require(WindowIndex.target(from: wellFormed))
        #expect(target.id == 42)
        #expect(target.layer == 0)
        #expect(target.cgFrame == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func fullyTransparentWindowsAreNotCovered() {
        var info = wellFormed
        info[kCGWindowAlpha as String] = 0.0
        #expect(WindowIndex.target(from: info) == nil)
    }

    @Test func degenerateBoundsAreSkipped() {
        var info = wellFormed
        info[kCGWindowBounds as String] = ["X": 0, "Y": 0, "Width": 0, "Height": 200]
        #expect(WindowIndex.target(from: info) == nil)
    }

    @Test func missingOrMistypedKeysAreSkipped() {
        var mistyped = wellFormed
        mistyped[kCGWindowLayer as String] = "not a number"
        #expect(WindowIndex.target(from: mistyped) == nil)

        var missing = wellFormed
        missing[kCGWindowBounds as String] = nil
        #expect(WindowIndex.target(from: missing) == nil)
    }

    /// Menus, tooltips and panels are the H1 case: they must parse, not be
    /// filtered out for sitting on a non-zero layer or being small.
    @Test(arguments: [25, 101, 200]) func nonZeroLayersAreCovered(layer: Int) throws {
        var info = wellFormed
        info[kCGWindowLayer as String] = layer
        info[kCGWindowBounds as String] = ["X": 10, "Y": 10, "Width": 120, "Height": 40]
        let target = try #require(WindowIndex.target(from: info))
        #expect(target.layer == layer)
    }
}

@Suite("Frontmost app menu title")
@MainActor
struct FrontmostAppTests {
    @Test func anOrdinaryNameIsUsedAsIs() {
        #expect(FrontmostApp.displayName("Discord") == "Discord")
    }

    /// localizedName comes from the other app's Info.plist, so a name that would
    /// stretch or break the menu is cut rather than shown.
    @Test func anOverlongNameIsTruncated() {
        let title = FrontmostApp.displayName(String(repeating: "a", count: 200))
        #expect(title.count <= 33)
        #expect(title.hasSuffix("…"))
    }

    @Test func onlyTheFirstLineIsShown() {
        #expect(FrontmostApp.displayName("Discord\nQuit Nyx") == "Discord")
        #expect(FrontmostApp.displayName("Discord\r\nProtection: Off") == "Discord")
    }

    @Test(arguments: ["", "   ", "\n", "\n\n"])
    func anEmptyNameFallsBackToWording(raw: String) {
        #expect(FrontmostApp.displayName(raw) == "this app")
    }
}

@Suite("Overlay levels")
struct OverlayLevelTests {
    private let dock = Int(CGWindowLevelForKey(.dockWindow))
    private let screenSaver = Int(CGWindowLevelForKey(.screenSaverWindow))

    /// The whole of H1: a placeholder has to outrank the window it covers.
    @Test(arguments: [0, 3, 19, 20, 24, 25, 101, 102, 200, 500])
    func placeholderOutranksEveryLayerItCovers(layer: Int) {
        #expect(OverlayLevel.placeholder(coveringLayer: layer).rawValue > layer)
    }

    /// It must outrank it by exactly one, and no more: the levels above an
    /// ordinary window belong to the system, not to the protected app.
    @Test func anOrdinaryWindowIsCoveredOneLevelUp() {
        #expect(OverlayLevel.placeholder(coveringLayer: 0).rawValue == 1)
    }

    @Test func menusAndTooltipsGetMatchingHighLevels() {
        #expect(OverlayLevel.placeholder(coveringLayer: 101).rawValue == 102)
        #expect(OverlayLevel.placeholder(coveringLayer: 200).rawValue == 201)
    }

    /// The regression this guards: the Dock, the Cmd-Tab switcher, the menu bar
    /// and status menus all have to stay above the whole stack.
    @Test func ordinaryWindowsLeaveTheSystemUIOnTop() {
        let stack = [
            OverlayLevel.placeholder(coveringLayer: 0).rawValue,
            OverlayLevel.mirror(coveringLayers: [0, 0, 0]).rawValue,
        ]
        for level in stack {
            #expect(level < dock)
            #expect(level < Int(CGWindowLevelForKey(.mainMenuWindow)))
            #expect(level < Int(CGWindowLevelForKey(.popUpMenuWindow)))
            #expect(level < Int(CGWindowLevelForKey(.floatingWindow)))
        }
    }

    /// The mirror carries the live preview, so it has to clear every placeholder
    /// under it — including the one covering the app's own open menu.
    @Test(arguments: [[0], [0, 101], [0, 25, 200], [500], [Int.max / 2]])
    func mirrorOutranksEveryPlaceholderBelowIt(layers: [Int]) {
        let mirror = OverlayLevel.mirror(coveringLayers: layers).rawValue
        for layer in layers {
            #expect(OverlayLevel.placeholder(coveringLayer: layer).rawValue < mirror)
        }
    }

    /// Nothing Nyx draws may reach the screen saver: protected content must
    /// never be composited over a locked screen.
    @Test func nothingReachesTheScreenSaver() {
        #expect(OverlayLevel.mirror(coveringLayers: [Int.max / 2]).rawValue < screenSaver)
        #expect(OverlayLevel.placeholder(coveringLayer: Int.max / 2).rawValue < screenSaver)
    }

    /// The resnap hits this between an app being engaged and its first window
    /// appearing, and it must not yield a stale or out-of-range level.
    @Test func aWindowlessAppStillYieldsASaneMirrorLevel() {
        let mirror = OverlayLevel.mirror(coveringLayers: []).rawValue
        #expect(mirror > OverlayLevel.placeholder(coveringLayer: 0).rawValue)
        #expect(mirror < dock)
    }
}
