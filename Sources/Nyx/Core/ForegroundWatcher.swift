import AppKit

final class ForegroundWatcher {
    private let engine: OverlayEngine
    private let list: ProtectionList

    init(engine: OverlayEngine, list: ProtectionList) {
        self.engine = engine
        self.list = list
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
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier == engine.engagedPID else { return }
        Log.watcher.debug("protected app quit while engaged")
        engine.disengage()
    }

    // Engaging is keyed on the process, not on any window existing yet: the
    // engine covers whatever is on screen every frame, so restore-from-minimize
    // and late-created windows need no separate retry poll.
    private func evaluate(_ app: NSRunningApplication?) {
        guard list.protectionEnabled,
              let app, let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              list.contains(bundleID)
        else {
            engine.disengage()
            return
        }
        Log.watcher.debug("protected app frontmost: \(bundleID, privacy: .private)")
        engine.engage(pid: app.processIdentifier)
    }
}
