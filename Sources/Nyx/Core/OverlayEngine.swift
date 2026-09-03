import AppKit
import ScreenCaptureKit
import SwiftUI

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        // Non-opaque so macOS never reports the covered window as occluded —
        // Electron/Chromium apps stop rendering (frozen mirror) when occluded.
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.995)
        hasShadow = false
        ignoresMouseEvents = true
        // Above all app windows, below the Dock-owned Cmd+Tab switcher and menus.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
}

struct PlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.995)
            Text("Nyx is protecting this window")
                .font(Theme.font(22))
                .foregroundColor(.white)
        }
        .ignoresSafeArea()
    }
}

final class OverlayEngine: NSObject {
    private(set) var engagedPID: pid_t?
    var isEngaged: Bool { engagedPID != nil }
    var onStreamFailure: (() -> Void)?
    var onUserStoppedCapture: (() -> Void)?
    var onStateChange: ((Bool) -> Void)?

    private var placeholder: OverlayWindow?
    private var mirror: OverlayWindow?
    private var stream: SCStream?
    private var targetWindowID: CGWindowID = 0
    private var generation = 0
    private var lastFrameAt: CFTimeInterval = 0
    private var resnapTimer: Timer?
    private let sampleQueue = DispatchQueue(label: "nyx.mirror.frames")

    func engage(pid: pid_t) {
        let wasEngaged = isEngaged
        if wasEngaged { disengage(notify: false) }
        guard CGPreflightScreenCaptureAccess() else {
            Log.engine.error("cannot engage — no screen recording permission")
            if wasEngaged { onStateChange?(false) }
            return
        }
        guard let target = Self.frontmostWindow(of: pid) else {
            Log.engine.error("engage failed — no capturable window for pid \(pid, privacy: .private)")
            if wasEngaged { onStateChange?(false) }
            return
        }
        engagedPID = pid
        targetWindowID = target.id
        generation += 1
        lastFrameAt = CACurrentMediaTime()
        let frame = Self.appKitRect(fromCG: target.frame)

        let placeholder = OverlayWindow(frame: frame)
        placeholder.contentView = NSHostingView(rootView: PlaceholderView())

        let mirror = OverlayWindow(frame: frame)
        mirror.sharingType = .none
        mirror.contentView?.wantsLayer = true
        mirror.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.995).cgColor
        mirror.contentView?.layer?.contentsGravity = .resize

        placeholder.orderFront(nil)
        mirror.order(.above, relativeTo: placeholder.windowNumber)
        self.placeholder = placeholder
        self.mirror = mirror

        startStream(windowID: target.id, generation: generation)
        resnapTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.resnap()
        }
        Log.engine.debug("engaged pid \(pid, privacy: .private)")
        onStateChange?(true)
    }

    func disengage(notify: Bool = true) {
        guard isEngaged else { return }
        Log.engine.debug("disengage")
        engagedPID = nil
        targetWindowID = 0
        generation += 1
        resnapTimer?.invalidate()
        resnapTimer = nil
        if let stream {
            stream.stopCapture { error in
                if let error { Log.engine.error("stopCapture error: \(error.localizedDescription, privacy: .public)") }
            }
        }
        stream = nil
        placeholder?.orderOut(nil)
        mirror?.orderOut(nil)
        placeholder = nil
        mirror = nil
        if notify { onStateChange?(false) }
    }

    // MARK: - Window tracking

    private func resnap() {
        guard let pid = engagedPID else { return }
        guard let target = Self.frontmostWindow(of: pid) else {
            Log.engine.debug("target window gone, disengaging")
            disengage()
            return
        }
        if target.id != targetWindowID {
            Log.engine.debug("frontmost window changed within app, re-engaging")
            engage(pid: pid)
            return
        }
        let frame = Self.appKitRect(fromCG: target.frame)
        if let placeholder, placeholder.frame != frame {
            placeholder.setFrame(frame, display: true)
            mirror?.setFrame(frame, display: true)
            updateStreamSize(target.frame.size)
        }
        if lastFrameAt > 0, CACurrentMediaTime() - lastFrameAt > 2 {
            Log.engine.error("frame stall — no mirror frames")
            lastFrameAt = CACurrentMediaTime()
        }
    }

    static func frontmostWindow(of pid: pid_t) -> (id: CGWindowID, frame: CGRect)? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 64, frame.height >= 64
            else { continue }
            return (id, frame)
        }
        return nil
    }

    // CGWindowList is top-left-origin; AppKit is bottom-left of the primary screen.
    static func appKitRect(fromCG cg: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    // MARK: - Capture

    private func startStream(windowID: CGWindowID, generation gen: Int) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                if let error {
                    Log.engine.error("shareable content error: \(error.localizedDescription, privacy: .public)")
                    self.disengage()
                    self.onStreamFailure?()
                    return
                }
                guard let scWindow = content?.windows.first(where: { $0.windowID == windowID }) else {
                    Log.engine.error("SCK could not find the target window")
                    self.disengage()
                    return
                }
                self.beginCapture(of: scWindow)
            }
        }
    }

    private func beginCapture(of scWindow: SCWindow) {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        let scale = mirror?.screen?.backingScaleFactor ?? 2
        config.width = max(1, Int(scWindow.frame.width * scale))
        config.height = max(1, Int(scWindow.frame.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        } catch {
            Log.engine.error("addStreamOutput failed: \(error.localizedDescription, privacy: .public)")
            disengage()
            return
        }
        stream.startCapture { [weak self] error in
            guard let error else { return }
            Log.engine.error("startCapture failed: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async {
                self?.disengage()
                self?.onStreamFailure?()
            }
        }
        self.stream = stream
    }

    private func updateStreamSize(_ size: CGSize) {
        guard let stream else { return }
        let config = SCStreamConfiguration()
        let scale = mirror?.screen?.backingScaleFactor ?? 2
        config.width = max(1, Int(size.width * scale))
        config.height = max(1, Int(size.height * scale))
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 5
        stream.updateConfiguration(config) { error in
            if let error { Log.engine.error("updateConfiguration error: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

extension OverlayEngine: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              statusRaw == SCFrameStatus.complete.rawValue,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        lastFrameAt = CACurrentMediaTime()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEngaged else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.mirror?.contentView?.layer?.contents = surface
            CATransaction.commit()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.engine.error("stream stopped with error: \(error.localizedDescription, privacy: .public)")
        let nsError = error as NSError
        let userStopped = nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userStopped.rawValue
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEngaged else { return }
            self.disengage()
            if userStopped {
                self.onUserStoppedCapture?()
            } else {
                self.onStreamFailure?()
            }
        }
    }
}
