import AppKit

final class ForegroundWatcher {
    private let engine: OverlayEngine
    var protectedBundleIDs: Set<String> = ["com.apple.TextEdit"]

    init(engine: OverlayEngine) {
        self.engine = engine
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
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

    private func evaluate(_ app: NSRunningApplication?) {
        guard let app, let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              protectedBundleIDs.contains(bundleID)
        else {
            engine.disengage()
            return
        }
        guard engine.engagedPID != app.processIdentifier else { return }
        NSLog("nyx: protected app frontmost: \(bundleID)")
        engine.engage(pid: app.processIdentifier)
    }
}
