import AppKit

/// What the hotkey and the tray's protect item both act on. Nyx itself is out
/// because protecting it is meaningless, Finder because it owns the desktop.
@MainActor
struct FrontmostApp {
    let app: NSRunningApplication
    let bundleID: String

    private static let maxDisplayName = 32

    static var protectable: FrontmostApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              bundleID != "com.apple.finder"
        else { return nil }
        return FrontmostApp(app: app, bundleID: bundleID)
    }

    var displayName: String { Self.displayName(app.localizedName ?? bundleID) }

    /// A menu title, so it is cut to one line of menu-sized text: localizedName
    /// is whatever the other app's Info.plist happens to say.
    static func displayName(_ raw: String) -> String {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "this app" }
        guard trimmed.count > maxDisplayName else { return trimmed }
        return trimmed.prefix(maxDisplayName).trimmingCharacters(in: .whitespaces) + "…"
    }
}
