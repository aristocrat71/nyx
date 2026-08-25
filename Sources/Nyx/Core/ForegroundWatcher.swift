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

    private func evaluate(_ app: NSRunningApplication?) {
        guard list.protectionEnabled,
              let app, let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              list.contains(bundleID)
        else {
            engine.disengage()
            return
        }
        guard engine.engagedPID != app.processIdentifier else { return }
        NSLog("nyx: protected app frontmost: \(bundleID)")
        engine.engage(pid: app.processIdentifier)
    }
}
