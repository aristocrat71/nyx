import AppKit

NSLog("nyx: alive")

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = OverlayEngine()
    let list = ProtectionList()
    let hotkeys = HotkeyManager()
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
        engine.onStateChange = { [weak self] engaged in self?.engineStateChanged(engaged) }
        engine.onStreamFailure = { [weak self] in self?.streamFailed() }
        engine.onUserStoppedCapture = { [weak self] in
            NSLog("nyx: capture stopped from system UI — protection off")
            self?.list.protectionEnabled = false
        }
        tray.onOpenDashboard = { [weak self] in self?.dashboard.show() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        watcher.start()
        hotkeys.onHotkey = { [weak self] in self?.hotkeyToggled() }
        hotkeys.register(list.hotkey)
        if !model.hasScreenPermission || list.apps.isEmpty {
            dashboard.show()
        }
    }

    private func engineStateChanged(_ engaged: Bool) {
        model.isEngaged = engaged
        tray.setEngaged(engaged)
        if !engaged {
            DispatchQueue.main.async { [weak self] in self?.watcher.reevaluate() }
        }
    }

    private func streamFailed() {
        model.refreshPermission()
        if !model.hasScreenPermission {
            NSLog("nyx: screen recording permission lost mid-run")
            dashboard.show()
        }
    }

    @objc private func screensChanged() {
        guard engine.isEngaged else { return }
        NSLog("nyx: screen configuration changed, disengaging")
        engine.disengage()
    }

    private func hotkeyToggled() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              bundleID != "com.apple.finder"
        else {
            NSLog("nyx: hotkey ignored — can't protect this app")
            return
        }
        let name = app.localizedName ?? bundleID
        let nowProtected = list.toggle(bundleID: bundleID, name: name)
        NSLog("nyx: hotkey — \(name) \(nowProtected ? "protected" : "visible to viewers")")
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
