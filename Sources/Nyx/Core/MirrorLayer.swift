import AppKit
import ScreenCaptureKit

/// What the user sees through the placeholders: one capture-excluded window per
/// display, showing every window the protected app owns — including its menus,
/// which a per-window stream cannot follow.
@MainActor
final class MirrorLayer: NSObject {
    enum Failure {
        case noPermission
        case setupFailed
        case userStopped
    }

    var onFailure: ((Failure) -> Void)?
    var onRunning: (() -> Void)?

    private(set) var isRunning = false

    private var windows: [CGDirectDisplayID: MirrorWindow] = [:]
    private var streams: [CGDirectDisplayID: SCStream] = [:]
    private var outputs: [CGDirectDisplayID: DisplayOutput] = [:]
    private var presented: [CGDirectDisplayID: CVPixelBuffer] = [:]
    private var generation = 0
    private let sampleQueue = DispatchQueue(label: "nyx.mirror.frames")

    func start(pid: pid_t) {
        stop()
        generation += 1
        let gen = generation
        guard CGPreflightScreenCaptureAccess() else {
            onFailure?(.noPermission)
            return
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            let snapshot = Snapshot(content)
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                if let error {
                    Log.engine.error("shareable content error: \(error.localizedDescription, privacy: .public)")
                    self.onFailure?(.setupFailed)
                    return
                }
                let content = snapshot.content
                guard let app = content?.applications.first(where: { $0.processID == pid }) else {
                    // Normal right after launch: the app has no shareable
                    // windows yet. The retry backoff picks it up.
                    Log.engine.debug("protected app not shareable yet")
                    self.onFailure?(.setupFailed)
                    return
                }
                guard let displays = content?.displays, !displays.isEmpty else {
                    Log.engine.error("no shareable displays")
                    self.onFailure?(.setupFailed)
                    return
                }
                self.begin(app: app, displays: displays, generation: gen)
            }
        }
    }

    func stop() {
        generation += 1
        isRunning = false
        for stream in streams.values {
            stream.stopCapture { _ in }
        }
        streams.removeAll()
        outputs.removeAll()
        presented.removeAll()
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    private func begin(app: SCRunningApplication, displays: [SCDisplay], generation gen: Int) {
        guard let primaryHeight = WindowIndex.primaryScreenHeight else {
            onFailure?(.setupFailed)
            return
        }
        var started = 0
        for display in displays {
            let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            if #available(macOS 14.2, *) { filter.includeMenuBar = false }

            let stream = SCStream(filter: filter, configuration: Self.configuration(for: display), delegate: self)
            let output = DisplayOutput(displayID: display.displayID) { [weak self] id, buffer, surface in
                DispatchQueue.main.async {
                    self?.present(surface, buffer: buffer, on: id, generation: gen)
                }
            }
            do {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            } catch {
                Log.engine.error("addStreamOutput failed: \(error.localizedDescription, privacy: .public)")
                continue
            }

            let window = MirrorWindow()
            window.show(covering: WindowIndex.appKitRect(fromCG: display.frame, primaryHeight: primaryHeight))
            windows[display.displayID] = window
            streams[display.displayID] = stream
            outputs[display.displayID] = output
            started += 1

            stream.startCapture { [weak self] error in
                guard let error else { return }
                Log.engine.error("startCapture failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    guard let self, self.generation == gen else { return }
                    self.stop()
                    self.onFailure?(.setupFailed)
                }
            }
        }
        if started == 0 {
            stop()
            onFailure?(.setupFailed)
        }
    }

    private func present(_ surface: IOSurfaceRef, buffer: CVPixelBuffer, on displayID: CGDirectDisplayID, generation gen: Int) {
        guard generation == gen, let window = windows[displayID] else { return }
        window.present(surface)
        // Hold the parent buffer, not just the surface: SCK's pool recycles and
        // rewrites the surface underneath the compositor otherwise.
        presented[displayID] = buffer
        if !isRunning {
            isRunning = true
            onRunning?()
        }
    }

    private static func configuration(for display: SCDisplay) -> SCStreamConfiguration {
        let scale = WindowIndex.backingScale(of: display.displayID)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(CGFloat(display.width) * scale))
        config.height = max(1, Int(CGFloat(display.height) * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 3
        return config
    }
}

extension MirrorLayer: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let nsError = error as NSError
        let userStopped = nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userStopped.rawValue
        Log.engine.error("stream stopped: \(error.localizedDescription, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning || !self.streams.isEmpty else { return }
            self.stop()
            self.onFailure?(userStopped ? .userStopped : .setupFailed)
        }
    }
}

/// SCShareableContent and the objects it vends are immutable snapshots handed
/// over on ScreenCaptureKit's own queue and never touched again, so moving one
/// to the main queue is safe even though the type carries no Sendable promise.
private struct Snapshot: @unchecked Sendable {
    let content: SCShareableContent?

    init(_ content: SCShareableContent?) { self.content = content }
}

private final class DisplayOutput: NSObject, SCStreamOutput {
    private let displayID: CGDirectDisplayID
    private let onFrame: (CGDirectDisplayID, CVPixelBuffer, IOSurfaceRef) -> Void

    init(displayID: CGDirectDisplayID, onFrame: @escaping (CGDirectDisplayID, CVPixelBuffer, IOSurfaceRef) -> Void) {
        self.displayID = displayID
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        onFrame(displayID, pixelBuffer, surface)
    }
}
