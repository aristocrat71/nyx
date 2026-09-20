import AppKit

@MainActor
final class ForegroundWatcher {
    private let engine: OverlayEngine
    private let list: ProtectionList
    private let capture: CaptureWatcher
    private let tabs = TabWatcher()

    init(engine: OverlayEngine, list: ProtectionList, capture: CaptureWatcher) {
        self.engine = engine
        self.list = list
        self.capture = capture
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(listChanged),
            name: ProtectionList.changed,
            object: nil
        )
        capture.onChange = { [weak self] _ in self?.reevaluate() }
        tabs.onChange = { [weak self] in self?.reevaluate() }
        evaluate(NSWorkspace.shared.frontmostApplication)
    }

    func reevaluate() {
        evaluate(NSWorkspace.shared.frontmostApplication)
    }

    @objc private func appActivated(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        evaluate(app)
    }

    @objc private func listChanged() {
        reevaluate()
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        if app.processIdentifier == tabs.watchedPID { tabs.stop() }
        guard app.processIdentifier == engine.engagedPID else { return }
        Log.watcher.debug("protected app quit while engaged")
        engine.disengage()
    }

    // Engaging is keyed on the process, not on any window existing yet: the
    // engine covers whatever is on screen every frame, so restore-from-minimize
    // and late-created windows need no separate retry poll.
    private func evaluate(_ app: NSRunningApplication?) {
        // A mirror nobody is watching only lights the sharing indicator, so
        // nothing engages until some other process is capturing.
        guard list.protectionEnabled, capture.isCapturing,
              let app, let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier
        else {
            tabs.stop()
            engine.disengage()
            return
        }
        let appProtected = list.contains(bundleID)
        updateTabWatch(app, bundleID: bundleID, needed: !appProtected)
        guard appProtected || frontTabIsProtected() else {
            engine.disengage()
            return
        }
        // A mismatch still gets covered — refusing to cover would be the one
        // failure mode that shows content. It is worth saying out loud though:
        // the process holding this bundle identifier is not the code the user
        // pointed Nyx at.
        if let requirement = list.app(withBundleID: bundleID)?.requirement,
           !CodeIdentity.process(app.processIdentifier, satisfies: requirement) {
            Log.watcher.error("frontmost process does not match the pinned signing identity")
        }
        Log.watcher.debug("protected app frontmost: \(bundleID, privacy: .private)")
        engine.engage(pid: app.processIdentifier)
    }
}

extension ForegroundWatcher {
    /// Site rules only ever apply to a browser, and only while one is frontmost,
    /// so Nyx never reads the address bar in the background.
    private func updateTabWatch(_ app: NSRunningApplication, bundleID: String, needed: Bool) {
        guard needed, !list.sites.isEmpty, Browsers.isBrowser(bundleID) else {
            tabs.stop()
            return
        }
        tabs.watch(pid: app.processIdentifier)
    }

    private func frontTabIsProtected() -> Bool {
        guard let tab = tabs.currentTab() else { return false }
        if let host = tab.host {
            guard let site = list.sites.match(host: host) else { return false }
            Log.watcher.debug("front tab matches \(site.host, privacy: .private)")
            return true
        }
        // A browser that publishes no address leaves the window title as the
        // only signal there is.
        guard let title = tab.title, let site = list.sites.match(title: title) else { return false }
        Log.watcher.debug("front window title matches \(site.host, privacy: .private)")
        return true
    }
}
