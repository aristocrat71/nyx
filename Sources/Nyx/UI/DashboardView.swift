import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    @Published var isEngaged = false
    @Published var hasScreenPermission = CGPreflightScreenCaptureAccess()

    func refreshPermission() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != hasScreenPermission { hasScreenPermission = granted }
    }
}

final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var permissionTimer: Timer?

    init(list: ProtectionList, model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
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

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            if !model.hasScreenPermission { permissionBanner }
            appsSection
            divider
            statusLine
        }
        .frame(width: 420, height: 520)
        .background(Theme.background)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Nyx").font(Theme.font(14, medium: true)).foregroundColor(Theme.text)
            Spacer()
            Text("⌃⇧L").font(Theme.font(12)).foregroundColor(Theme.muted)
        }
        .padding(.leading, 76)
        .padding(.trailing, 16)
        .frame(height: 52)
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Text("Nyx needs Screen Recording to mirror your windows")
                .font(Theme.font(11))
                .foregroundColor(Theme.amber)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: openScreenRecordingSettings) {
                Text("Open Settings")
                    .font(Theme.font(11, medium: true))
                    .foregroundColor(Theme.backgroundNS.asColor)
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

    private var appsSection: some View {
        Group {
            if list.apps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PROTECTED APPS")
                            .font(Theme.font(11, medium: true))
                            .foregroundColor(Theme.muted)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        ForEach(list.apps) { app in
                            AppRow(app: app) { list.remove(bundleID: app.bundleID) }
                        }
                        addButton.padding(.top, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(!model.hasScreenPermission)
        .opacity(model.hasScreenPermission ? 1 : 0.4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Nothing protected yet.\nAdd an app, or press ⌃⇧L while using one.")
                .font(Theme.font(12))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            addButton
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var addButton: some View {
        Button { showingPicker = true } label: {
            Text("+ Add app…")
                .font(Theme.font(12))
                .foregroundColor(Theme.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            RunningAppsPicker(alreadyProtected: Set(list.apps.map(\.bundleID))) { app in
                if let bundleID = app.bundleIdentifier {
                    list.add(bundleID: bundleID, name: app.localizedName ?? bundleID)
                }
                showingPicker = false
            }
        }
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isEngaged ? Theme.amber : Theme.muted.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(model.isEngaged ? "Protection active" : "Idle")
                    .font(Theme.font(12))
                    .foregroundColor(model.isEngaged ? Theme.text : Theme.muted)
                Spacer()
            }
            Text("macOS shows a screen-sharing indicator while Nyx mirrors a window. The mirror never leaves your Mac.")
                .font(Theme.font(10))
                .foregroundColor(Theme.muted.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

private struct AppRow: View {
    let app: ProtectedApp
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: Self.icon(for: app.bundleID))
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name).font(Theme.font(13)).foregroundColor(Theme.text)
            Spacer()
            if hovering {
                Button(action: onRemove) {
                    Text("✕").font(Theme.font(12)).foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(hovering ? Color.white.opacity(0.03) : Color.clear)
        .onHover { hovering = $0 }
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

private struct RunningAppsPicker: View {
    let alreadyProtected: Set<String>
    let onPick: (NSRunningApplication) -> Void
    @State private var filter = ""
    @State private var apps: [NSRunningApplication] = []

    private var filtered: [NSRunningApplication] {
        guard !filter.isEmpty else { return apps }
        return apps.filter { ($0.localizedName ?? "").localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter…", text: $filter)
                .textFieldStyle(.plain)
                .font(Theme.font(12))
                .foregroundColor(Theme.text)
                .padding(10)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.processIdentifier) { app in
                        PickerRow(app: app) { onPick(app) }
                    }
                }
            }
        }
        .frame(width: 260, height: 320)
        .background(Theme.panel)
        .background(CaptureExcluded())
        .onAppear(perform: load)
    }

    private func load() {
        apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.processIdentifier != NSRunningApplication.current.processIdentifier
                    && app.bundleIdentifier.map { !alreadyProtected.contains($0) } ?? false
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

private struct PickerRow: View {
    let app: NSRunningApplication
    let onPick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon ?? NSImage())
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(app.localizedName ?? app.bundleIdentifier ?? "unknown")
                    .font(Theme.font(12))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(hovering ? Color.white.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private extension NSColor {
    var asColor: Color { Color(nsColor: self) }
}
