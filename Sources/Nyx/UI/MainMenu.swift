import AppKit

// An accessory app draws no menu bar, but AppKit still routes ⌘X/⌘C/⌘V, ⌘W and
// ⌘Q through the main menu — without one those keys do nothing in the dashboard.
enum MainMenu {
    static func install() {
        let main = NSMenu()
        main.addItem(submenu(named: "Nyx", items: [
            ("Quit Nyx", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        // Selectors by name: the editing ones are responder-chain messages with no
        // single class to take #selector of, and NSText.copy collides with NSObject's.
        main.addItem(submenu(named: "Edit", items: [
            ("Undo", Selector(("undo:")), "z"),
            ("Redo", Selector(("redo:")), "Z"),
            ("Cut", Selector(("cut:")), "x"),
            ("Copy", Selector(("copy:")), "c"),
            ("Paste", Selector(("paste:")), "v"),
            ("Select All", Selector(("selectAll:")), "a"),
        ]))
        main.addItem(submenu(named: "Window", items: [
            ("Close", #selector(NSWindow.performClose(_:)), "w"),
        ]))
        NSApp.mainMenu = main
    }

    private static func submenu(named name: String, items: [(String, Selector, String)]) -> NSMenuItem {
        let menu = NSMenu(title: name)
        for (title, action, key) in items {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }
}
