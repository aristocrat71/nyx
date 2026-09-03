import AppKit

Log.ui.debug("alive")

@MainActor
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
            Log.ui.error("screen recording permission missing — requesting")
            CGRequestScreenCaptureAccess()
        }
        engine.onStateChange = { [weak self] state in self?.engineStateChanged(state) }
        engine.onPermissionLost = { [weak self] in self?.permissionLost() }
        engine.onUserStoppedCapture = { [weak self] in
            Log.engine.error("capture stopped from system UI — protection off")
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
        if !model.hasScreenPermission || list.loadFailed || list.apps.isEmpty {
            dashboard.show()
        }
    }

    private func engineStateChanged(_ state: ProtectionState) {
        model.state = state
        tray.setState(state)
    }

    private func permissionLost() {
        model.refreshPermission()
        guard !model.hasScreenPermission else { return }
        Log.engine.error("screen recording permission lost mid-run")
        dashboard.show()
    }

    @objc private func screensChanged() {
        Log.engine.debug("screen configuration changed, rebuilding the mirror")
        engine.displaysChanged()
    }

    private func hotkeyToggled() {
        guard let front = FrontmostApp.protectable else {
            Log.ui.debug("hotkey ignored — can't protect this app")
            return
        }
        let nowProtected = list.toggle(front.app)
        Log.ui.debug("hotkey — \(front.displayName, privacy: .private) \(nowProtected ? "protected" : "visible to viewers", privacy: .public)")
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
