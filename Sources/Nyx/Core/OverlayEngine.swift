import AppKit

enum ProtectionState: Equatable {
    case idle
    /// Covered and mirrored: viewers see black, the user sees their app.
    case active
    /// Covered but the mirror is not running. The content is still hidden from
    /// viewers; the user cannot see through it either.
    case blind
}

final class OverlayEngine: NSObject {
    /// Fast enough that a drag cannot outrun the placeholder by more than the
    /// bleed margin, and cheap enough to leave running while engaged.
    private static let resnapInterval: TimeInterval = 1.0 / 60
    private static let minRetryDelay: TimeInterval = 0.5
    private static let maxRetryDelay: TimeInterval = 30

    private(set) var engagedPID: pid_t?
    private(set) var state: ProtectionState = .idle

    var isEngaged: Bool { engagedPID != nil }
    var onStateChange: ((ProtectionState) -> Void)?
    var onUserStoppedCapture: (() -> Void)?
    var onPermissionLost: (() -> Void)?

    private let placeholders = PlaceholderLayer()
    private let mirror = MirrorLayer()
    private var resnapTimer: Timer?
    private var retry: DispatchWorkItem?
    private var retryDelay = OverlayEngine.minRetryDelay

    override init() {
        super.init()
        mirror.onRunning = { [weak self] in
            self?.retryDelay = OverlayEngine.minRetryDelay
            self?.publish(.active)
        }
        mirror.onFailure = { [weak self] failure in self?.mirrorFailed(failure) }
    }

    func engage(pid: pid_t) {
        guard engagedPID != pid else { return }
        tearDown()
        engagedPID = pid
        // Cover first, from CGWindowList alone, before anything that can fail
        // or go async has a chance to run.
        resnap()
        let timer = Timer(timeInterval: Self.resnapInterval, repeats: true) { [weak self] _ in
            self?.resnap()
        }
        RunLoop.main.add(timer, forMode: .common)
        resnapTimer = timer
        publish(.blind)
        mirror.start(pid: pid)
        Log.engine.debug("engaged pid \(pid, privacy: .private)")
    }

    func disengage() {
        guard isEngaged else { return }
        tearDown()
        publish(.idle)
        Log.engine.debug("disengaged")
    }

    /// A projector arriving is exactly when a share starts, so the mirror is
    /// rebuilt for the new display set without ever dropping cover.
    func displaysChanged() {
        guard let pid = engagedPID else { return }
        retry?.cancel()
        retry = nil
        publish(.blind)
        mirror.start(pid: pid)
    }

    private func tearDown() {
        engagedPID = nil
        resnapTimer?.invalidate()
        resnapTimer = nil
        retry?.cancel()
        retry = nil
        retryDelay = Self.minRetryDelay
        mirror.stop()
        placeholders.clear()
    }

    private func resnap() {
        guard let pid = engagedPID else { return }
        placeholders.cover(WindowIndex.onScreenWindows(of: pid))
    }

    private func mirrorFailed(_ failure: MirrorLayer.Failure) {
        guard let pid = engagedPID else { return }
        publish(.blind)
        switch failure {
        case .userStopped:
            // An explicit click on the system "Stop Sharing" is the one thing
            // allowed to drop protection.
            onUserStoppedCapture?()
        case .noPermission:
            onPermissionLost?()
            scheduleRetry(pid: pid)
        case .setupFailed:
            scheduleRetry(pid: pid)
        }
    }

    /// Backoff, not a tight loop: the placeholders stay up between attempts, so
    /// a permanently failing stream never strobes the protected window.
    private func scheduleRetry(pid: pid_t) {
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.engagedPID == pid else { return }
            self.mirror.start(pid: pid)
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
        retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
    }

    private func publish(_ new: ProtectionState) {
        guard state != new else { return }
        state = new
        onStateChange?(new)
    }
}
