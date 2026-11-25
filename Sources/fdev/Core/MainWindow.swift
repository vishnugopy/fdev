import SwiftUI
import AppKit

/// The full fdev window, opened from the menu or the action wheel.
/// Managed directly (not a SwiftUI scene) so it can be opened from anywhere, e.g. a global hotkey.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()
    private var window: NSWindow?

    func show(tool: Tool? = nil) {
        if let tool {
            UserDefaults.standard.set(tool.rawValue, forKey: "route")
            UserDefaults.standard.set(tool.rawValue, forKey: "lastTool")
        }
        let w = window ?? make()
        if !w.isVisible { DockPresence.windowOpened() } else { NSApp.activate() }
        w.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let host = NSHostingController(rootView:
            RootView(inWindow: true)
                .background(VisualEffectBackground().ignoresSafeArea())
        )
        host.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "fdev"
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setFrameAutosaveName("fdev.main")
        if !w.setFrameUsingName("fdev.main") { w.center() }
        window = w
        return w
    }

    func windowWillClose(_ notification: Notification) {
        DockPresence.windowClosed()
    }
}

/// Same material as the menu bar panel, so the window and the menu look alike.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
