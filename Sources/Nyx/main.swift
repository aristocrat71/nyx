import AppKit

NSLog("nyx: alive")

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = OverlayEngine()
    let list = ProtectionList()
    let hotkeys = HotkeyManager()
    let toasts = ToastCenter()
    let model = AppModel()
    lazy var watcher = ForegroundWatcher(engine: engine, list: list)
    lazy var tray = TrayController(list: list)
    lazy var dashboard = DashboardWindowController(list: list, model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerBundledFonts()
        if !CGPreflightScreenCaptureAccess() {
            NSLog("nyx: screen recording permission missing — requesting")
            CGRequestScreenCaptureAccess()
        }
        engine.onStateChange = { [weak self] engaged in
            self?.model.isEngaged = engaged
            self?.tray.setEngaged(engaged)
        }
        tray.onOpenDashboard = { [weak self] in self?.dashboard.show() }
        watcher.start()
        hotkeys.onHotkey = { [weak self] in self?.hotkeyToggled() }
        hotkeys.register(list.hotkey)
        if !model.hasScreenPermission || list.apps.isEmpty {
            dashboard.show()
        }
    }

    private func hotkeyToggled() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              bundleID != "com.apple.finder"
        else {
            toasts.show("Can't protect this app", accent: false)
            return
        }
        let name = app.localizedName ?? bundleID
        let nowProtected = list.toggle(bundleID: bundleID, name: name)
        toasts.show(nowProtected ? "\(name) protected" : "\(name) visible to viewers", accent: nowProtected)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.disengage()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

signal(SIGINT, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler { NSApp.terminate(nil) }
sigintSource.resume()

app.run()
