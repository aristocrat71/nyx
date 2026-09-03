import AppKit
import Carbon.HIToolbox
import Combine

struct ProtectedApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    /// Designated requirement captured when the app was added. Absent for
    /// entries written before pinning existed, and for unsigned apps.
    var requirement: String?
    var id: String { bundleID }

    static let maxNameLength = 128

    static let maxRequirementLength = 2048

    var isWellFormed: Bool {
        guard !bundleID.isEmpty, bundleID.count <= 255, name.count <= Self.maxNameLength,
              (requirement?.count ?? 0) <= Self.maxRequirementLength
        else { return false }
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

    func add(bundleID: String, name: String, requirement: String? = nil) {
        let app = ProtectedApp(
            bundleID: bundleID,
            name: String(name.prefix(ProtectedApp.maxNameLength)),
            requirement: requirement
        )
        guard !contains(bundleID), app.isWellFormed, apps.count < Self.maxApps else { return }
        apps.append(app)
        persistAndNotify()
    }

    func app(withBundleID bundleID: String) -> ProtectedApp? {
        apps.first { $0.bundleID == bundleID }
    }

    func remove(bundleID: String) {
        apps.removeAll { $0.bundleID == bundleID }
        persistAndNotify()
    }

    /// Returns true if the app is protected after the toggle.
    @discardableResult
    func toggle(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        if contains(bundleID) {
            remove(bundleID: bundleID)
            return false
        }
        add(app)
        return contains(bundleID)
    }

    func add(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        add(
            bundleID: bundleID,
            name: app.localizedName ?? bundleID,
            requirement: app.bundleURL.flatMap(CodeIdentity.designatedRequirement(ofBundleAt:))
        )
    }

    struct Loaded: Equatable {
        var apps: [ProtectedApp] = []
        var hotkey = ProtectionList.defaultHotkey
        var droppedApps = 0
        var rejectedHotkey = false
        var failed = false
    }

    /// Everything a hostile or corrupt file can influence, in one pure function
    /// so it can be tested without touching Application Support.
    static func decode(_ data: Data) -> Loaded {
        guard let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return Loaded(failed: true)
        }
        var result = Loaded()
        result.apps = Array(store.apps.filter(\.isWellFormed).prefix(maxApps))
        result.droppedApps = store.apps.count - result.apps.count
        if let stored = store.hotkey {
            if stored.isWellFormed { result.hotkey = stored } else { result.rejectedHotkey = true }
        }
        // A stored "off" is deliberately not read back: turning protection off
        // should take an action in this session, not a file that any same-user
        // process can rewrite while Nyx is not running.
        return result
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            Log.store.debug("no protected.json yet, starting empty")
            return
        }
        let result = Self.decode(data)
        guard !result.failed else {
            Log.store.error("failed to decode protected.json")
            loadFailed = true
            return
        }
        apps = result.apps
        hotkey = result.hotkey
        if result.droppedApps > 0 {
            Log.store.error("dropped \(result.droppedApps, privacy: .public) malformed entries")
        }
        if result.rejectedHotkey {
            Log.store.error("stored hotkey rejected, keeping the default")
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
