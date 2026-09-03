import Foundation
import os

/// Which app the user has open, and when, is exactly what Nyx exists to hide —
/// so nothing identifying is logged in the clear, and routine activity stays at
/// `.debug`, which the unified log keeps in memory rather than on disk.
enum Log {
    private static let subsystem = "tech.unravel.nyx"

    static let engine = Logger(subsystem: subsystem, category: "engine")
    static let watcher = Logger(subsystem: subsystem, category: "watcher")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
