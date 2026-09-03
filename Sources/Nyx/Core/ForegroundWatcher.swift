import AppKit

final class ForegroundWatcher {
    private let engine: OverlayEngine
    private let list: ProtectionList
    private var retryTimer: Timer?

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

    private func evaluate(_ app: NSRunningApplication?) {
        defer { updateRetryTimer() }
        guard list.protectionEnabled,
              let app, let bundleID = app.bundleIdentifier,
              app.processIdentifier != NSRunningApplication.current.processIdentifier,
              list.contains(bundleID)
        else {
            engine.disengage()
            return
        }
        guard engine.engagedPID != app.processIdentifier else { return }
        Log.watcher.debug("protected app frontmost: \(bundleID, privacy: .private)")
        engine.engage(pid: app.processIdentifier)
    }

    // Covers restore-from-minimize and windows that appear after activation:
    // poll only while a protected app is frontmost but nothing is engaged.
    private func updateRetryTimer() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let shouldPoll = list.protectionEnabled
            && !engine.isEngaged
            && frontmost?.processIdentifier != NSRunningApplication.current.processIdentifier
            && list.contains(frontmost?.bundleIdentifier)
        if shouldPoll {
            guard retryTimer == nil else { return }
            retryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.reevaluate()
            }
        } else {
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }
}
