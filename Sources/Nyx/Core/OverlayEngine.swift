import AppKit
import ScreenCaptureKit
import SwiftUI

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
}

struct PlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 14) {
                Text("Nyx is protecting this window")
                    .font(Theme.font(22))
                    .foregroundColor(.white)
                Text("🦉")
                    .font(.system(size: 13))
                    .opacity(0.55)
            }
        }
        .ignoresSafeArea()
    }
}

final class OverlayEngine: NSObject {
    private(set) var engagedPID: pid_t?
    var isEngaged: Bool { engagedPID != nil }
    var onStreamFailure: (() -> Void)?
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
        if isEngaged { disengage() }
        guard let target = Self.frontmostWindow(of: pid) else {
            NSLog("nyx: engage failed — no capturable window for pid \(pid)")
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
        mirror.contentView?.layer?.backgroundColor = NSColor.black.cgColor
        mirror.contentView?.layer?.contentsGravity = .resize

        placeholder.orderFront(nil)
        mirror.order(.above, relativeTo: placeholder.windowNumber)
        self.placeholder = placeholder
        self.mirror = mirror

        startStream(windowID: target.id, generation: generation)
        resnapTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.resnap()
        }
        NSLog("nyx: engaged pid \(pid) window \(target.id) frame \(NSStringFromRect(frame))")
        onStateChange?(true)
    }

    func disengage() {
        guard isEngaged else { return }
        NSLog("nyx: disengage pid \(engagedPID ?? -1)")
        engagedPID = nil
        targetWindowID = 0
        generation += 1
        resnapTimer?.invalidate()
        resnapTimer = nil
        if let stream {
            stream.stopCapture { error in
                if let error { NSLog("nyx: stopCapture error: \(error.localizedDescription)") }
            }
        }
        stream = nil
        placeholder?.orderOut(nil)
        mirror?.orderOut(nil)
        placeholder = nil
        mirror = nil
        onStateChange?(false)
    }

    // MARK: - Window tracking

    private func resnap() {
        guard let pid = engagedPID else { return }
        guard let target = Self.frontmostWindow(of: pid) else {
            NSLog("nyx: target window gone, disengaging")
            disengage()
            return
        }
        if target.id != targetWindowID {
            NSLog("nyx: frontmost window changed within app, re-engaging")
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
            NSLog("nyx: frame stall — no mirror frames for \(Int(CACurrentMediaTime() - lastFrameAt))s")
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
                    NSLog("nyx: shareable content error: \(error.localizedDescription)")
                    self.disengage()
                    self.onStreamFailure?()
                    return
                }
                guard let scWindow = content?.windows.first(where: { $0.windowID == windowID }) else {
                    NSLog("nyx: SCK could not find window \(windowID)")
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
            NSLog("nyx: addStreamOutput failed: \(error.localizedDescription)")
            disengage()
            return
        }
        stream.startCapture { [weak self] error in
            guard let error else { return }
            NSLog("nyx: startCapture failed: \(error.localizedDescription)")
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
            if let error { NSLog("nyx: updateConfiguration error: \(error.localizedDescription)") }
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
        NSLog("nyx: stream stopped with error: \(error.localizedDescription)")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEngaged else { return }
            self.disengage()
            self.onStreamFailure?()
        }
    }
}
