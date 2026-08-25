import AppKit

NSLog("nyx: alive")

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = OverlayEngine()
    lazy var watcher = ForegroundWatcher(engine: engine)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CGPreflightScreenCaptureAccess() {
            NSLog("nyx: screen recording permission missing — requesting")
            CGRequestScreenCaptureAccess()
        }
        watcher.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.disengage()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

signal(SIGINT, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler { NSApp.terminate(nil) }
sigintSource.resume()

app.run()
