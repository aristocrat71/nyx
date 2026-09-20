import AppKit
import ApplicationServices

/// What the accessibility tree will say about a browser's front tab. Either
/// field can be absent: Firefox exposes no URL, only a window title.
struct BrowserTab: Equatable {
    var host: String?
    var title: String?

    var isEmpty: Bool { host == nil && title == nil }
}

enum Browsers {
    static let bundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "app.zen-browser.zen",
        "com.kagi.kagimacOS",
    ]

    static func isBrowser(_ bundleID: String) -> Bool { bundleIDs.contains(bundleID) }
}
