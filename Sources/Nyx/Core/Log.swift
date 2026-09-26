import Foundation
import os

/// Which app is open, and when, is what Nyx exists to hide: nothing identifying
/// is logged in the clear, and routine activity stays at in-memory `.debug`.
enum Log {
    private static let subsystem = "tech.unravel.nyx"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let watcher = Logger(subsystem: subsystem, category: "watcher")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
