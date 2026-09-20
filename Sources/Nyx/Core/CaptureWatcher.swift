import AppKit

/// Whether any process is capturing the screen, read from WindowServer's
/// screen-watcher flag. Needs no permission, but counts Nyx's own mirror too.
@MainActor
final class CaptureWatcher {
    /// WindowServer's capture-started and capture-stopped notifications. They
    /// carry no payload and only arrive inside the NSApplication run loop.
    private static let captureStarted: UInt32 = 1502
    private static let captureStopped: UInt32 = 1503
    /// Whether the notifications fire for a second capturer is unverified, so
    /// the flag is polled as well.
    private static let pollInterval: TimeInterval = 1

    private(set) var isCapturing = false
    var onChange: ((Bool) -> Void)?

    private var pollTimer: Timer?

    nonisolated static var isSupported: Bool {
        SkyLight.isScreenWatcherPresent != nil && SkyLight.registerNotifyProc != nil
    }

    func start() {
        guard Self.isSupported, let register = SkyLight.registerNotifyProc else {
            // Fail closed: without the flag Nyx goes back to covering every
            // protected app, which shows the indicator but never leaks content.
            Log.watcher.error("screen-watcher flag unavailable — treating the screen as always captured")
            isCapturing = true
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for kind in [Self.captureStarted, Self.captureStopped] {
            let status = register(Self.notify, kind, context)
            if status != 0 {
                Log.watcher.error("registering WindowServer notification \(kind, privacy: .public) failed: \(status, privacy: .public)")
            }
        }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        refresh()
    }

    /// The watcher lives as long as the process, so the registration is never
    /// removed and the unretained context pointer stays valid.
    private static let notify: SkyLight.NotifyProc = { _, _, _, context in
        guard let context else { return }
        let watcher = Unmanaged<CaptureWatcher>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in watcher.refresh() }
    }

    private func refresh() {
        guard let isPresent = SkyLight.isScreenWatcherPresent else { return }
        let now = isPresent()
        guard now != isCapturing else { return }
        isCapturing = now
        Log.watcher.debug("screen capture \(now ? "started" : "stopped", privacy: .public)")
        onChange?(now)
    }
}

/// The two SkyLight entry points behind the flag, resolved by name so the
/// private framework is never linked.
private enum SkyLight {
    typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void
    typealias IsScreenWatcherPresent = @convention(c) () -> Bool
    typealias RegisterNotifyProc = @convention(c) (NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32

    static let isScreenWatcherPresent: IsScreenWatcherPresent? = symbol("SLSIsScreenWatcherPresent")
    static let registerNotifyProc: RegisterNotifyProc? = symbol("SLSRegisterNotifyProc")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let address = dlsym(handle, name)
        else { return nil }
        return unsafeBitCast(address, to: T.self)
    }
}
