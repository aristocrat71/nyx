import AppKit
import ApplicationServices

/// Watches one browser process for tab and navigation changes. Runs only while
/// that browser is frontmost and something is capturing, never in the background.
@MainActor
final class TabWatcher {
    /// A backstop for the notifications, which not every browser sends for an
    /// in-page navigation.
    private static let pollInterval: TimeInterval = 0.35

    private static let notifications = [
        kAXFocusedUIElementChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXTitleChangedNotification,
        kAXValueChangedNotification,
    ]

    var onChange: (() -> Void)?
    private(set) var watchedPID: pid_t?

    private var observer: AXObserver?
    private var timer: Timer?
    private var lastTab: BrowserTab?

    func watch(pid: pid_t) {
        guard watchedPID != pid else { return }
        stop()
        watchedPID = pid
        startObserver(pid: pid)
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard watchedPID != nil else { return }
        watchedPID = nil
        lastTab = nil
        timer?.invalidate()
        timer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
    }

    /// The tab as of now, read fresh. Nil when accessibility is not granted or
    /// the browser told us nothing.
    func currentTab() -> BrowserTab? {
        guard let pid = watchedPID else { return nil }
        let tab = BrowserTabReader.read(pid: pid)
        lastTab = tab
        return tab
    }

    private func startObserver(pid: pid_t) {
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let created else {
            Log.watcher.debug("no accessibility observer for pid \(pid, privacy: .private)")
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            AXObserverAddNotification(created, app, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
    }

    /// Delivered on the main run loop, which is where the source was added.
    private static let callback: AXObserverCallback = { _, _, _, context in
        guard let context else { return }
        let watcher = Unmanaged<TabWatcher>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { watcher.recheck() }
    }

    private func recheck() {
        guard let pid = watchedPID else { return }
        let tab = BrowserTabReader.read(pid: pid)
        guard tab != lastTab else { return }
        lastTab = tab
        onChange?()
    }
}
