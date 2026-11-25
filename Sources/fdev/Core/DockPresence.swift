import AppKit

/// fdev lives in the menu bar, but shows in the Dock / ⌘Tab while any of its windows are open
/// (main window, Settings).
@MainActor
enum DockPresence {
    private static var open = 0

    static func windowOpened() {
        open += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func windowClosed() {
        open = max(0, open - 1)
        if open == 0 { NSApp.setActivationPolicy(.accessory) }
    }
}
