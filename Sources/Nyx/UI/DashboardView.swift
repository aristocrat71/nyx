import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    private static let darkKey = "nyx.dashboard.dark"

    @Published var state: ProtectionState = .idle
    @Published var hasScreenPermission = CGPreflightScreenCaptureAccess()
    @Published var hasAccessibilityPermission = BrowserTabReader.isTrusted
    /// Starts on whatever the Mac is set to, then follows the settings picker.
    /// Read from the global default rather than NSApp, which is nil until the
    /// application object exists.
    @Published var isDark: Bool = UserDefaults.standard.object(forKey: darkKey) as? Bool
        ?? (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
    {
        didSet { UserDefaults.standard.set(isDark, forKey: Self.darkKey) }
    }

    var appearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }

    func refreshPermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != hasScreenPermission { hasScreenPermission = granted }
        let trusted = BrowserTabReader.isTrusted
        if trusted != hasAccessibilityPermission { hasAccessibilityPermission = trusted }
    }
}

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var permissionTimer: Timer?
    private var appearanceObserver: AnyCancellable?

    init(list: ProtectionList, model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Set on this window alone, so the button never reaches the tray icon
        // or anything else Nyx draws.
        window.appearance = model.appearance
        window.backgroundColor = Theme.backgroundNS
        window.isMovableByWindowBackground = true
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = NSHostingView(rootView: DashboardView(list: list, model: model))
        window.center()
        super.init(window: window)
        window.delegate = self
        appearanceObserver = model.$isDark.sink { [weak window] dark in
            window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        model.refreshPermission()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.model.refreshPermission()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        permissionTimer?.invalidate()
        permissionTimer = nil
        sender.orderOut(nil)
        return false
    }
}

struct DashboardView: View {
    @ObservedObject var list: ProtectionList
    @ObservedObject var model: AppModel
    @State private var showingPicker = false
    @State private var showingSettings = false
    @State private var siteField = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            if !model.hasScreenPermission { permissionBanner }
            if !list.sites.isEmpty && !model.hasAccessibilityPermission { accessibilityBanner }
            if list.loadFailed { loadFailureBanner }
            appsSection
            divider
            footer
        }
        .frame(width: 420, height: 540)
        .background(Theme.background)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    /// The traffic lights float over the top-left of a full-size content view,
    /// so the first row is theirs and the wordmark starts below them.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                settingsButton
            }
            .frame(height: 30)
            .padding(.trailing, 12)

            HStack(spacing: 12) {
                logoTile
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nyx")
                        .font(Theme.font(17, medium: true))
                        .foregroundColor(Theme.text)
                    Text("Screen-share privacy")
                        .font(Theme.font(11))
                        .foregroundColor(Theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private var logoTile: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(Theme.control)
            .overlay {
                if let owl = Theme.owl {
                    Image(nsImage: owl)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 28)
                        .foregroundColor(Theme.text)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.controlBorder, lineWidth: 1))
            .frame(width: 46, height: 46)
    }

    private var settingsButton: some View {
        Button { showingSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.muted)
                .frame(width: 26, height: 24)
                .background(Theme.control)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.controlBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Settings")
        .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
            SettingsPopover(model: model)
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Text("Nyx needs Screen Recording to mirror your windows")
                .font(Theme.font(11))
                .foregroundColor(Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: openScreenRecordingSettings) {
                Text("Open Settings")
                    .font(Theme.font(11, medium: true))
                    .foregroundColor(Theme.inkOnAmber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.amber.opacity(0.12))
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Text("Nyx needs Accessibility to read the browser's address bar")
                .font(Theme.font(11))
                .foregroundColor(Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: openAccessibilitySettings) {
                Text("Open Settings")
                    .font(Theme.font(11, medium: true))
                    .foregroundColor(Theme.inkOnAmber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.amber)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.amber.opacity(0.12))
    }

    private var loadFailureBanner: some View {
        Text("Nyx could not read your saved list — nothing is protected until you add an app again. The file is at ~/Library/Application Support/Nyx/protected.json.")
            .font(Theme.font(11))
            .foregroundColor(Theme.danger)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.danger.opacity(0.12))
    }

    private var appsSection: some View {
        Group {
            if list.apps.isEmpty && list.sites.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionLabel("PROTECTED APPS").padding(.top, 16)
                        ForEach(list.apps) { app in
                            AppRow(app: app) { list.remove(bundleID: app.bundleID) }
                        }
                        addButton.padding(.top, 8)
                        sectionLabel("PROTECTED SITES").padding(.top, 22)
                        ForEach(list.sites) { site in
                            SiteRow(site: site) { list.removeSite(host: site.host) }
                        }
                        siteEntry
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(!model.hasScreenPermission)
        .opacity(model.hasScreenPermission ? 1 : 0.4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(11, medium: true))
            .foregroundColor(Theme.muted)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    private var siteEntry: some View {
        VStack(alignment: .leading, spacing: 5) {
            siteInputRow
            if !siteField.isEmpty && ProtectedSite.normalize(siteField) == nil {
                Text("Enter a host like youtube.com, or paste a page address.")
                    .font(Theme.font(10))
                    .foregroundColor(Theme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var siteInputRow: some View {
        HStack(spacing: 8) {
            TextField("youtube.com", text: $siteField)
                .textFieldStyle(.plain)
                .font(Theme.font(12))
                .foregroundColor(Theme.text)
                .onSubmit(commitSite)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Theme.control)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.controlBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button(action: commitSite) {
                Text("Add").pill()
            }
            .buttonStyle(.plain)
            .disabled(ProtectedSite.normalize(siteField) == nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            if let owl = Theme.owl {
                Image(nsImage: owl)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 72)
                    .foregroundColor(Theme.muted.opacity(0.35))
            }
            Text("Nothing protected yet.\nAdd an app, or press ⌃⇧L while using one.")
                .font(Theme.font(12))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            addButton
            Text("Or cover a site whenever it is your front tab.")
                .font(Theme.font(11))
                .foregroundColor(Theme.muted)
                .padding(.top, 6)
            siteEntry
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var addButton: some View {
        Button { showingPicker = true } label: {
            Text("+ Add app…").pill()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            AppPicker(alreadyProtected: Set(list.apps.map(\.bundleID))) { app in
                list.add(app)
                showingPicker = false
            }
        }
    }

    /// Idle carries no status row: an app doing nothing is the resting state and
    /// does not need announcing. Engaged states still do.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.state != .idle { statusRow }
            HStack(spacing: 9) {
                Text("⌃⇧L")
                    .font(Theme.font(11, medium: true))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.control)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.controlBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("Protect the app you're using, or unprotect it.")
                    .font(Theme.font(11))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.state == .blind ? Theme.danger : Theme.amberText)
                    .frame(width: 6, height: 6)
                Text(model.state == .blind ? "Hidden — no local preview" : "Protection active")
                    .font(Theme.font(12))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            if model.state == .blind {
                Text("Viewers see the placeholder, but Nyx cannot mirror the window back to you. Retrying.")
                    .font(Theme.font(10))
                    .foregroundColor(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 2)
    }

    private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        BrowserTabReader.requestTrust()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func commitSite() {
        guard list.addSite(siteField) != nil else { return }
        siteField = ""
        if !model.hasAccessibilityPermission { BrowserTabReader.requestTrust() }
    }
}

/// Built rather than taken from the stock segmented style, which brings the
/// system accent into a window that is otherwise monochrome.
private struct AppearancePicker: View {
    @Binding var isDark: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("Light", selected: !isDark) { isDark = false }
            Rectangle().fill(Theme.controlBorder).frame(width: 1, height: 22)
            segment("Dark", selected: isDark) { isDark = true }
        }
        .background(Theme.control)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.controlBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(11, medium: true))
                .foregroundColor(selected ? Theme.text : Theme.muted)
                .frame(width: 62, height: 24)
                .background(selected ? Theme.selection : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

/// A popover is its own window and does not inherit the dashboard's sharing
/// type, so it is excluded from capture the way the app picker is.
struct SettingsPopover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .font(Theme.font(10, medium: true))
                .foregroundColor(Theme.muted)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

            HStack {
                Text("Appearance")
                    .font(Theme.font(12))
                    .foregroundColor(Theme.text)
                Spacer()
                AppearancePicker(isDark: $model.isDark)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                Text("macOS shows a screen-sharing indicator while Nyx mirrors a window, which only happens during a share. The mirror never leaves your Mac.")
                    .font(Theme.font(11))
                    .foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        .frame(width: 310)
        .background(Theme.panel)
        .background(CaptureExcluded())
    }
}

/// Buttons in this window are all text, so they need a border to read as
/// controls rather than as labels.
private extension View {
    func pill() -> some View {
        font(Theme.font(11, medium: true))
            .foregroundColor(Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.control)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.controlBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SiteRow: View {
    let site: ProtectedSite
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(site.host).font(Theme.font(13)).foregroundColor(Theme.text)
            Spacer()
            Button(action: onRemove) {
                Text("Remove")
                    .font(Theme.font(10, medium: true))
                    .foregroundColor(hovering ? Theme.text : Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(hovering ? Theme.control : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Theme.controlBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Stop covering \(site.host)")
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(hovering ? Theme.rowHighlight : Color.clear)
        .onHover { hovering = $0 }
    }
}

private struct AppRow: View {
    let app: ProtectedApp
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.icon(for: app))
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name).font(Theme.font(13)).foregroundColor(Theme.text)
            Spacer()
            Button(action: onRemove) {
                Text("Remove")
                    .font(Theme.font(10, medium: true))
                    .foregroundColor(hovering ? Theme.text : Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(hovering ? Theme.control : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Theme.controlBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Stop protecting \(app.name)")
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(hovering ? Theme.rowHighlight : Color.clear)
        .onHover { hovering = $0 }
    }

}

/// LaunchServices resolves a bundle identifier to whichever bundle currently
/// claims it, so an app that squats a protected identifier could put its own
/// artwork in this list. Icons are only taken from a bundle that satisfies the
/// identity pinned when the app was added.
@MainActor
private enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for app: ProtectedApp) -> NSImage {
        if let cached = cache[app.bundleID] { return cached }
        let image = resolve(app)
        cache[app.bundleID] = image
        return image
    }

    private static func resolve(_ app: ProtectedApp) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        if let requirement = app.requirement, !CodeIdentity.bundle(at: url, satisfies: requirement) {
            Log.ui.error("bundle claiming a protected identifier does not match its pinned identity")
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct AppPicker: View {
    let alreadyProtected: Set<String>
    let onPick: (InstalledApp) -> Void
    @State private var filter = ""
    @State private var apps: [InstalledApp] = []

    private var filtered: [InstalledApp] {
        guard !filter.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter…", text: $filter)
                .textFieldStyle(.plain)
                .font(Theme.font(12))
                .foregroundColor(Theme.text)
                .padding(10)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { app in
                        PickerRow(app: app) { onPick(app) }
                    }
                }
            }
        }
        .frame(width: 260, height: 360)
        .background(Theme.panel)
        .background(CaptureExcluded())
        .task { await load() }
    }

    /// Running apps show at once; the folder scan fills in the rest.
    private func load() async {
        let running = InstalledApps.running()
        apps = InstalledApps.merge(running, excluding: alreadyProtected)
        let installed = await Task.detached { InstalledApps.installed() }.value
        apps = InstalledApps.merge(running, installed, excluding: alreadyProtected)
    }
}

private struct PickerRow: View {
    let app: InstalledApp
    let onPick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(app.name)
                    .font(Theme.font(12))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(hovering ? Theme.rowHighlight : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
