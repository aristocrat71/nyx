import AppKit
import Combine

struct ProtectedApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
}

final class ProtectionList: ObservableObject {
    static let changed = Notification.Name("nyx.protectionList.changed")

    @Published private(set) var apps: [ProtectedApp] = []
    @Published var protectionEnabled: Bool = true {
        didSet { if !isLoading { persistAndNotify() } }
    }
    // ⌃⇧L — Carbon controlKey|shiftKey, kVK_ANSI_L
    var hotkey = HotkeySpec(keyCode: 37, carbonModifiers: 0x1000 | 0x0200)
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
    }

    func contains(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return apps.contains { $0.bundleID == bundleID }
    }

    func add(bundleID: String, name: String) {
        guard !contains(bundleID) else { return }
        apps.append(ProtectedApp(bundleID: bundleID, name: name))
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
        return true
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: Self.fileURL) else {
            Log.store.debug("no protected.json yet, starting empty")
            return
        }
        do {
            let store = try JSONDecoder().decode(Store.self, from: data)
            apps = store.apps
            if let hk = store.hotkey { hotkey = hk }
            if let enabled = store.protectionEnabled { protectionEnabled = enabled }
        } catch {
            Log.store.error("failed to decode protected.json: \(error.localizedDescription, privacy: .private)")
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
                withIntermediateDirectories: true
            )
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            Log.store.error("failed to save protected.json: \(error.localizedDescription, privacy: .private)")
        }
    }
}
