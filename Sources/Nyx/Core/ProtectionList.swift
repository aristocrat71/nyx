import AppKit
import Carbon.HIToolbox
import Combine

struct ProtectedApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }

    static let maxNameLength = 128

    var isWellFormed: Bool {
        guard !bundleID.isEmpty, bundleID.count <= 255, name.count <= Self.maxNameLength else { return false }
        return bundleID.unicodeScalars.allSatisfy(Self.bundleIDScalars.contains)
    }

    private static let bundleIDScalars = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: ".-_"))
}

struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    private static let allowedModifiers = UInt32(cmdKey | shiftKey | optionKey | controlKey)
    private static let requiredModifiers = UInt32(cmdKey | optionKey | controlKey)

    /// The spec goes straight to RegisterEventHotKey, so it is checked before
    /// use: a real virtual key code, only real modifier bits, and at least one
    /// non-shift modifier so a file cannot bind a bare letter key.
    var isWellFormed: Bool {
        keyCode < 128
            && carbonModifiers & ~Self.allowedModifiers == 0
            && carbonModifiers & Self.requiredModifiers != 0
    }
}

final class ProtectionList: ObservableObject {
    static let changed = Notification.Name("nyx.protectionList.changed")
    static let defaultHotkey = HotkeySpec(keyCode: 37, carbonModifiers: UInt32(controlKey | shiftKey))
    private static let maxApps = 200

    @Published private(set) var apps: [ProtectedApp] = []
    @Published var protectionEnabled: Bool = true {
        didSet { if !isLoading { persistAndNotify() } }
    }
    /// Set when the stored list could not be read. The file is left untouched
    /// so the user can recover it, and the dashboard says so rather than
    /// quietly presenting an empty list as "nothing to protect".
    @Published private(set) var loadFailed = false

    var hotkey = ProtectionList.defaultHotkey
    private var isLoading = false

    private struct Store: Codable {
        var apps: [ProtectedApp]
        var hotkey: HotkeySpec?
        var protectionEnabled: Bool?
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nyx/protected.json")
    }

    init() {
        load()
        tightenPermissions()
    }

    /// Runs on every launch, not just on save, so installs created before this
    /// existed stop being world-readable.
    private func tightenPermissions() {
        let fm = FileManager.default
        let directory = Self.fileURL.deletingLastPathComponent()
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        guard fm.fileExists(atPath: Self.fileURL.path) else { return }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }

    func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return apps.contains { $0.bundleID == bundleID }
    }

    func add(bundleID: String, name: String) {
        let app = ProtectedApp(bundleID: bundleID, name: String(name.prefix(ProtectedApp.maxNameLength)))
        guard !contains(bundleID), app.isWellFormed, apps.count < Self.maxApps else { return }
        apps.append(app)
        persistAndNotify()
    }

    func remove(bundleID: String) {
        apps.removeAll { $0.bundleID == bundleID }
        persistAndNotify()
    }

    /// Returns true if the app is protected after the toggle.
    @discardableResult
    func toggle(bundleID: String, name: String) -> Bool {
        if contains(bundleID) {
            remove(bundleID: bundleID)
            return false
        }
        add(bundleID: bundleID, name: name)
        return contains(bundleID)
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            Log.store.debug("no protected.json yet, starting empty")
            return
        }
        let store: Store
        do {
            store = try JSONDecoder().decode(Store.self, from: data)
        } catch {
            Log.store.error("failed to decode protected.json: \(error.localizedDescription, privacy: .private)")
            loadFailed = true
            return
        }
        apps = Array(store.apps.filter(\.isWellFormed).prefix(Self.maxApps))
        if store.apps.count != apps.count {
            Log.store.error("dropped \(store.apps.count - self.apps.count, privacy: .public) malformed entries")
        }
        if let stored = store.hotkey, stored.isWellFormed {
            hotkey = stored
        } else if store.hotkey != nil {
            Log.store.error("stored hotkey rejected, keeping the default")
        }
        // A stored "off" is deliberately not honoured: turning protection off
        // should take an action in this session, not a file that any same-user
        // process can rewrite while Nyx is not running.
        if store.protectionEnabled == false {
            Log.store.debug("ignoring persisted protectionEnabled=false")
        }
    }

    private func persistAndNotify() {
        save()
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    private func save() {
        let store = Store(apps: apps, hotkey: hotkey, protectionEnabled: protectionEnabled)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: Self.fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path
            )
            loadFailed = false
        } catch {
            Log.store.error("failed to save protected.json: \(error.localizedDescription, privacy: .private)")
        }
    }
}
