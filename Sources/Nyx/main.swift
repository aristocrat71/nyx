import AppKit

NSLog("nyx: alive")

final class DebugDriver: NSObject, NSApplicationDelegate {
    let engine = OverlayEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CGPreflightScreenCaptureAccess() {
            NSLog("nyx: screen recording permission missing — requesting")
            CGRequestScreenCaptureAccess()
        }
        guard let textEdit = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
            NSLog("nyx: TextEdit is not running — open it and relaunch")
            NSApp.terminate(nil)
            return
        }
        engine.engage(pid: textEdit.processIdentifier)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.engine.resnap()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = DebugDriver()
app.delegate = delegate

signal(SIGINT, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler {
    delegate.engine.disengage()
    NSApp.terminate(nil)
}
sigintSource.resume()

app.run()
