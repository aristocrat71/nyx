import AppKit
import ApplicationServices

/// Reads a browser's front tab out of the accessibility tree. One permission
/// covers every browser, and the reads are in-process, so this can run often.
@MainActor
enum BrowserTabReader {
    /// A browser that stops answering must not stall Nyx's main thread, so the
    /// reads are given far less time than the accessibility default of 6s.
    private static let messagingTimeout: Float = 0.2
    private static let maxDepth = 8
    private static let maxChildren = 40
    private static let maxNodes = 300

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The constant is a global var the compiler will not let us touch across
    /// actors, and its value is stable.
    private static let promptOption = "AXTrustedCheckOptionPrompt"

    @discardableResult
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions([Self.promptOption: true] as CFDictionary)
    }

    /// Chrome-family builds keep the web tree out of the accessibility API
    /// until something asks for it. Asked once per browser, not once per read.
    static func enableWebTree(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func read(pid: pid_t) -> BrowserTab? {
        guard isTrusted else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let window = element(attribute(app, kAXFocusedWindowAttribute)) else { return nil }

        var tab = BrowserTab()
        tab.title = attribute(window, kAXTitleAttribute) as? String
        tab.host = documentHost(of: window) ?? webAreaHost(under: window)
        return tab.isEmpty ? nil : tab
    }

    /// Safari puts the front tab's address on the window itself, which saves
    /// walking the tree at all.
    private static func documentHost(of window: AXUIElement) -> String? {
        guard let document = attribute(window, kAXDocumentAttribute) as? String else { return nil }
        return URL(string: document)?.host
    }

    private static func webAreaHost(under root: AXUIElement) -> String? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < maxNodes {
            let (node, depth) = queue.removeFirst()
            visited += 1
            if attribute(node, kAXRoleAttribute) as? String == "AXWebArea", let host = host(of: node) {
                return host
            }
            guard depth < maxDepth else { continue }
            let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children.prefix(maxChildren) { queue.append((child, depth + 1)) }
        }
        return nil
    }

    private static func host(of webArea: AXUIElement) -> String? {
        if let url = attribute(webArea, kAXURLAttribute) as? URL { return url.host }
        if let text = attribute(webArea, kAXURLAttribute) as? String { return URL(string: text)?.host }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
