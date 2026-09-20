import Foundation
import Testing
@testable import Nyx

@Suite("installed apps")
struct InstalledAppsTests {
    private func app(_ bundleID: String, _ name: String, _ path: String) -> InstalledApp {
        InstalledApp(bundleID: bundleID, name: name, url: URL(fileURLWithPath: path))
    }

    @Test func theApplicationsFoldersAreScanned() {
        let apps = InstalledApps.installed()
        #expect(apps.contains { $0.bundleID == "com.apple.TextEdit" })
        #expect(apps.allSatisfy { !$0.name.isEmpty && !$0.name.hasSuffix(".app") })
    }

    @Test func backgroundOnlyAppsAreLeftOut() {
        #expect(InstalledApps.app(at: URL(fileURLWithPath: "/System/Library/CoreServices/Dock.app")) == nil)
        #expect(InstalledApps.app(at: URL(fileURLWithPath: "/System/Applications/TextEdit.app")) != nil)
    }

    @Test func mergeDropsDuplicatesKeepsTheFirstCopyAndSortsByName() {
        let running = [app("b", "Beta", "/running/Beta.app")]
        let installed = [app("b", "Beta", "/Applications/Beta.app"), app("a", "alpha", "/Applications/alpha.app"),
                         app("x", "Excluded", "/Applications/Excluded.app")]
        let merged = InstalledApps.merge(running, installed, excluding: ["x"])
        #expect(merged.map(\.bundleID) == ["a", "b"])
        #expect(merged[1].url.path == "/running/Beta.app")
    }
}
