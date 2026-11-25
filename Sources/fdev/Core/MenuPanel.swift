import SwiftUI
import AppKit

/// The menu bar dropdown. fdev manages it itself (instead of SwiftUI's MenuBarExtra) so it can be
/// pinned: a pinned dropdown stays open while you click Finder or other apps — e.g. to drag files in.
@MainActor
final class MenuPanel: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = MenuPanel()

    @Published var pinned = false {
        didSet { if !pinned, isOpen, NSApp.keyWindow !== panel { close() } }
    }

    /// True while files are being dragged near the menu bar icon — the home list shows drop targets.
    @Published var dragActive = false
    private var dragMonitor: Any?
    private var dragEndMonitor: Any?
    private var lastDragChange = -1

    private var item: NSStatusItem?
    private var panel: DropdownPanel?
    private var outsideClick: Any?
    var isOpen: Bool { panel?.isVisible == true }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = LogoArtwork.menuBarImage
        item.button?.image?.accessibilityDescription = "fdev"
        self.item = item
        if let button = item.button {
            // Files dragged straight onto the icon.
            let drop = StatusDropView(frame: button.bounds)
            drop.autoresizingMask = [.width, .height]
            button.addSubview(drop)
        }
        watchDrags()
    }

    // MARK: Drag toward the menu bar → open with drop targets

    /// Global mouse monitors need no permission. While a drag carrying image files comes within
    /// reach of the icon, the dropdown opens on its own.
    private func watchDrags() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { _ in
            Task { @MainActor in MenuPanel.shared.dragMoved() }
        }
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            Task { @MainActor in MenuPanel.shared.dragEnded() }
        }
    }

    private func dragMoved() {
        guard !dragActive, let iconFrame else { return }
        let m = NSEvent.mouseLocation
        // Open early — well before the cursor reaches the top edge, where macOS would switch to
        // Mission Control. Zone: 260pt either side of the icon, from 40pt to 320pt below the menu bar.
        let near = NSRect(x: iconFrame.midX - 260, y: iconFrame.minY - 320, width: 520, height: 320 - 40 + 4)
        guard near.contains(m) else { return }
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != lastDragChange else { return }
        guard Self.imageURLs(from: pb).isEmpty == false || NSImage.canInit(with: pb) else { return }
        lastDragChange = pb.changeCount
        openForDrop()
    }

    func openForDrop() {
        dragActive = true
        UserDefaults.standard.set("home", forKey: "route")
        if !isOpen { open() }
    }

    private func dragEnded() {
        // The mouse-up arrives *before* macOS delivers the drop to our tile — removing the tiles now
        // would make the drop miss. Wait a beat; a successful drop clears them itself.
        guard dragActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Task { @MainActor in
                let me = MenuPanel.shared
                if me.dragActive { me.dragActive = false }
            }
        }
    }

    func dropFinished() { dragActive = false; lastDragChange = NSPasteboard(name: .drag).changeCount }

    private var iconFrame: NSRect? {
        guard let button = item?.button, let w = button.window else { return nil }
        return w.convertToScreen(button.convert(button.bounds, to: nil))
    }

    nonisolated static func imageURLs(from pb: NSPasteboard) -> [URL] {
        let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"],
        ]) as? [URL]
        return urls ?? []
    }

    @objc func toggle() { isOpen ? close() : open() }

    func open() {
        let p = panel ?? make()
        position(p)
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        item?.button?.highlight(true)
        // Clicks in other apps close it — unless pinned.
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            Task { @MainActor in
                let me = MenuPanel.shared
                if !me.pinned && !me.dragActive { me.close() }
            }
        }
    }

    /// Always closes, pinned or not (used by actions that need the screen, like picking a color).
    func close() {
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        outsideClick = nil
        panel?.orderOut(nil)
        item?.button?.highlight(false)
    }

    private func make() -> DropdownPanel {
        let host = NSHostingController(rootView:
            RootView(inWindow: false)
                .background(VisualEffectBackground())
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        )
        host.sizingOptions = [.preferredContentSize]
        let p = DropdownPanel(contentRect: .init(x: 0, y: 0, width: Metrics.panelWidth, height: 400),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.delegate = self
        panel = p
        return p
    }

    /// Hang the panel under the menu bar icon; keep it on screen.
    private func position(_ p: NSPanel) {
        guard let button = item?.button, let bw = button.window else { return }
        let b = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        let size = p.frame.size
        var x = b.minX
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        p.setFrameTopLeftPoint(NSPoint(x: x, y: b.minY - 4))
    }

    // Content height changes as you navigate — keep the top edge pinned under the icon.
    func windowDidResize(_ notification: Notification) {
        guard let p = panel, p.isVisible else { return }
        position(p)
        p.invalidateShadow()
    }
}

/// Sits on top of the menu bar icon: forwards clicks, and opens the dropdown when files are dragged onto it.
final class StatusDropView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .tiff, .png])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { Task { @MainActor in MenuPanel.shared.toggle() } }
    override func rightMouseDown(with event: NSEvent) { Task { @MainActor in MenuPanel.shared.toggle() } }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Task { @MainActor in MenuPanel.shared.openForDrop() }
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    // Dropping on the icon itself: default to Remove Background.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = MenuPanel.imageURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        Task { @MainActor in DropTarget.background.receive(urls) }
        return true
    }
}

enum DropTarget: CaseIterable {
    case background, convert
    var tool: Tool { self == .background ? .background : .image }

    /// Finder gives file URLs; browsers and Photos give image data — save that to a temp file.
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for (i, p) in providers.enumerated() {
            if p.hasItemConformingToTypeIdentifier("public.file-url"),
               let d = try? await p.loadItem(forTypeIdentifier: "public.file-url") as? Data,
               let u = URL(dataRepresentation: d, relativeTo: nil) {
                urls.append(u)
            } else if p.hasItemConformingToTypeIdentifier("public.image") {
                let data: Data? = await withCheckedContinuation { c in
                    p.loadDataRepresentation(forTypeIdentifier: "public.image") { d, _ in c.resume(returning: d) }
                }
                if let data, let rep = NSBitmapImageRep(data: data),
                   let png = rep.representation(using: .png, properties: [:]) {
                    let u = FileManager.default.temporaryDirectory.appendingPathComponent("dropped-\(i + 1).png")
                    if (try? png.write(to: u)) != nil { urls.append(u) }
                }
            }
        }
        return urls
    }

    @MainActor func receive(_ urls: [URL]) {
        MenuPanel.shared.dropFinished()
        MenuPanel.shared.pinned = true            // stay open so the result can be dragged out again
        UserDefaults.standard.set(tool.rawValue, forKey: "route")
        UserDefaults.standard.set(tool.rawValue, forKey: "lastTool")
        if !MenuPanel.shared.isOpen { MenuPanel.shared.open() }
        switch self {
        case .background: BackgroundRemoverModel.shared.load(urls: urls)
        case .convert: if let u = urls.first { ImageConvertModel.shared.load(url: u) }
        }
    }
}

/// Big drop tiles shown at the top of the dropdown while an image is being dragged in.
struct DropTargetsView: View {
    var body: some View {
        HStack(spacing: 8) {
            Tile(target: .background, title: "Remove Background", symbol: Tool.background.icon)
            Tile(target: .convert, title: "Convert Image", symbol: Tool.image.icon)
        }
        .padding(.horizontal, Metrics.inset)
        .padding(.vertical, 6)
    }

    private struct Tile: View {
        let target: DropTarget
        let title: String
        let symbol: String
        @State private var over = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            VStack(spacing: 8) {
                IconCircle(symbol: symbol, active: over, size: 36)
                Text(title).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center)
                Text("Drop here").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(shape.fill(over ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06)))
            .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(over ? Color.accentColor : Color.primary.opacity(0.25)))
            .animation(.easeOut(duration: 0.12), value: over)
            .onDrop(of: [.fileURL, .image], isTargeted: $over) { providers in
                Task {
                    let urls = await DropTarget.urls(from: providers)
                    await MainActor.run { if !urls.isEmpty { target.receive(urls) } }
                }
                return true
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Drop images to \(title)")
        }
    }
}

final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { MenuPanel.shared.close() }   // Esc
}

/// Settings, managed directly so it can be opened from the dropdown panel and the action wheel.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        MenuPanel.shared.close()
        let w = window ?? make()
        if !w.isVisible { DockPresence.windowOpened() } else { NSApp.activate() }
        w.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView())
        host.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.title = "fdev Settings"
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        return w
    }

    func windowWillClose(_ notification: Notification) { DockPresence.windowClosed() }
}

/// Pin toggle shown in the dropdown's header.
struct PinButton: View {
    @ObservedObject private var menu = MenuPanel.shared
    var body: some View {
        Button { menu.pinned.toggle() } label: {
            Image(systemName: menu.pinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(menu.pinned ? 0 : 45))
                .foregroundStyle(menu.pinned ? Color.accentColor : .secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(menu.pinned ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(menu.pinned ? "Pinned — stays open when you click other apps. Click to unpin."
                          : "Pin open — keep this menu open while you drag files from Finder")
        .accessibilityLabel(menu.pinned ? "Unpin menu" : "Pin menu open")
        .accessibilityAddTraits(menu.pinned ? .isSelected : [])
    }
}
