import AppKit

/// An app the picker can offer: installed in one of the Applications folders,
/// or running from anywhere else.
struct InstalledApp: Identifiable, Hashable, Sendable {
    let bundleID: String
    let name: String
    let url: URL
    var id: String { bundleID }
}

enum InstalledApps {
    private static let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
    /// Two levels: Utilities-style subfolders count, nothing deeper does.
    private static let maxDepth = 2

    @MainActor
    static func running() -> [InstalledApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular,
                  app.processIdentifier != NSRunningApplication.current.processIdentifier,
                  let bundleID = app.bundleIdentifier, let url = app.bundleURL
            else { return nil }
            return InstalledApp(bundleID: bundleID, name: app.localizedName ?? bundleID, url: url)
        }
    }

    nonisolated static func installed() -> [InstalledApp] {
        var found: [InstalledApp] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: [],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    enumerator.skipDescendants()
                    if let app = app(at: url) { found.append(app) }
                } else if enumerator.level >= maxDepth {
                    enumerator.skipDescendants()
                }
            }
        }
        return found
    }

    /// Earlier lists win a duplicate identifier, so callers pass the running
    /// copy first and a protected app is pinned to the code actually in use.
    nonisolated static func merge(_ lists: [InstalledApp]..., excluding excluded: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for app in lists.joined() where !excluded.contains(app.bundleID) && seen.insert(app.bundleID).inserted {
            result.append(app)
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func app(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier, !isBackgroundOnly(bundle) else {
            return nil
        }
        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return InstalledApp(bundleID: bundleID, name: name, url: url)
    }

    /// Menu-bar-only and faceless apps never come to the front, so protecting
    /// one would do nothing.
    private nonisolated static func isBackgroundOnly(_ bundle: Bundle) -> Bool {
        ["LSUIElement", "LSBackgroundOnly"].contains { key in
            switch bundle.object(forInfoDictionaryKey: key) {
            case let flag as Bool: flag
            case let flag as String: ["1", "yes", "true"].contains(flag.lowercased())
            default: false
            }
        }
    }
}
