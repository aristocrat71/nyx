import AppKit
import ServiceManagement

final class TrayController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let list: ProtectionList
    var onOpenDashboard: (() -> Void)?

    private static let idleImage = owlImage(filled: false, dot: false)
    private static let activeImage = owlImage(filled: true, dot: true)

    init(list: ProtectionList) {
        self.list = list
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = Self.idleImage
        statusItem.button?.toolTip = "Nyx"
    }

    func setEngaged(_ engaged: Bool) {
        statusItem.button?.image = engaged ? Self.activeImage : Self.idleImage
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
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
                NSLog("nyx: launch at login off")
            } else {
                try SMAppService.mainApp.register()
                NSLog("nyx: launch at login on")
            }
        } catch {
            NSLog("nyx: launch at login toggle failed: \(error.localizedDescription)")
        }
    }

    @objc private func toggleProtection() {
        list.protectionEnabled.toggle()
        NSLog("nyx: protection \(list.protectionEnabled ? "on" : "off")")
    }

    @objc private func openDashboard() { onOpenDashboard?() }

    @objc private func quit() { NSApp.terminate(nil) }

    // Idle is a template outline; active is filled in labelColor with an amber dot
    // (template images can't carry color, so the active variant resolves at draw time).
    private static func owlImage(filled: Bool, dot: Bool) -> NSImage {
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
            if dot {
                Theme.amberNS.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 0.5, width: 5, height: 5)).fill()
            }
            return true
        }
        image.isTemplate = !dot
        return image
    }
}
