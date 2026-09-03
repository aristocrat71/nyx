import AppKit
import ServiceManagement

final class TrayController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let list: ProtectionList
    var onOpenDashboard: (() -> Void)?

    private static let idleImage = owlImage(filled: false, dotColor: nil)
    private static let activeImage = owlImage(filled: true, dotColor: Theme.amberNS)
    private static let blindImage = owlImage(filled: true, dotColor: Theme.dangerNS)

    init(list: ProtectionList) {
        self.list = list
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = Self.idleImage
        statusItem.button?.toolTip = "Nyx"
    }

    func setState(_ state: ProtectionState) {
        switch state {
        case .idle:
            statusItem.button?.image = Self.idleImage
            statusItem.button?.toolTip = "Nyx — idle"
        case .active:
            statusItem.button?.image = Self.activeImage
            statusItem.button?.toolTip = "Nyx — protecting this window"
        case .blind:
            statusItem.button?.image = Self.blindImage
            statusItem.button?.toolTip = "Nyx — window hidden, no local preview"
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        CaptureExclusion.excludeMenuWindows()
        menu.removeAllItems()

        let toggle = NSMenuItem(
            title: list.protectionEnabled ? "Protection: On" : "Protection: Off",
            action: #selector(toggleProtection),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.state = list.protectionEnabled ? .on : .off
        menu.addItem(toggle)

        let dashboard = NSMenuItem(title: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "")
        dashboard.target = self
        menu.addItem(dashboard)

        menu.addItem(.separator())

        let launch = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launch.target = self
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launch)

        let quit = NSMenuItem(title: "Quit Nyx", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                Log.ui.debug("launch at login off")
            } else {
                try SMAppService.mainApp.register()
                Log.ui.debug("launch at login on")
            }
        } catch {
            Log.ui.error("launch at login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func toggleProtection() {
        list.protectionEnabled.toggle()
        Log.ui.debug("protection \(self.list.protectionEnabled ? "on" : "off", privacy: .public)")
    }

    @objc private func openDashboard() { onOpenDashboard?() }

    @objc private func quit() { NSApp.terminate(nil) }

    // Idle is a template outline; the engaged variants are filled in labelColor
    // with a status dot (template images can't carry color, so those resolve at
    // draw time): amber while mirroring, red while hidden without a preview.
    private static func owlImage(filled: Bool, dotColor: NSColor?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let ink: NSColor = filled ? .labelColor : .black

            let body = NSBezierPath(ovalIn: NSRect(x: 3.5, y: 2.5, width: 11, height: 12))
            let ears = NSBezierPath()
            ears.move(to: NSPoint(x: 4.5, y: 12)); ears.line(to: NSPoint(x: 5, y: 16.5)); ears.line(to: NSPoint(x: 8.5, y: 13.5)); ears.close()
            ears.move(to: NSPoint(x: 13.5, y: 12)); ears.line(to: NSPoint(x: 13, y: 16.5)); ears.line(to: NSPoint(x: 9.5, y: 13.5)); ears.close()
            let leftEye = NSBezierPath(ovalIn: NSRect(x: 5.2, y: 7.7, width: 3.4, height: 3.4))
            let rightEye = NSBezierPath(ovalIn: NSRect(x: 9.4, y: 7.7, width: 3.4, height: 3.4))

            ink.set()
            ears.fill()
            if filled {
                body.fill()
                NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
                leftEye.fill()
                rightEye.fill()
                NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
            } else {
                body.lineWidth = 1.3
                body.stroke()
                leftEye.lineWidth = 1.1
                leftEye.stroke()
                rightEye.lineWidth = 1.1
                rightEye.stroke()
            }
            if let dotColor {
                dotColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 0.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = dotColor == nil
        return image
    }
}
