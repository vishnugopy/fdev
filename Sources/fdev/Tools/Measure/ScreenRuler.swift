import AppKit

/// Full-screen overlay for measuring anything on screen (⌥⌘M).
/// Drag to draw a box · ↩ or ⌘C copies "W×H" · Esc closes. No Screen Recording needed.
@MainActor
final class ScreenRuler {
    static let shared = ScreenRuler()
    private var windows: [NSWindow] = []

    var isActive: Bool { !windows.isEmpty }

    func start() {
        stop()
        if let w = NSApp.keyWindow, w is NSPanel { w.orderOut(nil) }
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let w = RulerWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.acceptsMouseMovedEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = RulerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.scale = screen.backingScaleFactor
            w.contentView = v
            w.orderFrontRegardless()
            if screen.frame.contains(mouse) { w.makeKey(); w.makeFirstResponder(v) }
            windows.append(w)
        }
        NSApp.activate()
    }

    func stop() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    func finish(copy size: CGSize?) {
        stop()
        if let size {
            Clipboard.copy("\(Int(size.width.rounded()))×\(Int(size.height.rounded()))", symbol: "ruler")
        }
    }
}

final class RulerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class RulerView: NSView {
    var scale: CGFloat = 2
    private var start: NSPoint?
    private var end: NSPoint?
    private var mouse: NSPoint?

    private var rect: NSRect? {
        guard let start, let end else { return nil }
        let r = NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
                       width: abs(start.x - end.x), height: abs(start.y - end.y))
        return r.width >= 1 || r.height >= 1 ? r : nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self))
    }

    private func snap(_ e: NSEvent) -> NSPoint {
        let p = convert(e.locationInWindow, from: nil)
        return NSPoint(x: p.x.rounded(), y: p.y.rounded())
    }

    override func mouseMoved(with e: NSEvent) { mouse = snap(e); needsDisplay = true }
    override func mouseEntered(with e: NSEvent) { window?.makeKey(); window?.makeFirstResponder(self) }
    override func mouseExited(with e: NSEvent) { mouse = nil; needsDisplay = true }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2, let r = rect { Task { @MainActor in ScreenRuler.shared.finish(copy: r.size) }; return }
        start = snap(e); end = start; mouse = start; needsDisplay = true
    }
    override func mouseDragged(with e: NSEvent) { end = snap(e); mouse = end; needsDisplay = true }
    override func mouseUp(with e: NSEvent) { end = snap(e); needsDisplay = true }

    override func keyDown(with e: NSEvent) {
        let size = rect?.size
        switch e.keyCode {
        case 53: Task { @MainActor in ScreenRuler.shared.finish(copy: nil) }               // Esc
        case 36, 76: Task { @MainActor in ScreenRuler.shared.finish(copy: size) }           // Return
        case 8 where e.modifierFlags.contains(.command):                                    // ⌘C
            Task { @MainActor in ScreenRuler.shared.finish(copy: size) }
        default: super.keyDown(with: e)
        }
    }

    override func draw(_ dirty: NSRect) {
        // Light dim so the overlay is clearly "on", while content stays readable.
        NSColor.black.withAlphaComponent(0.12).setFill()
        bounds.fill()

        let accent = NSColor.systemPink

        if let r = rect {
            NSColor.clear.setFill()
            r.fill(using: .copy)                          // undim the measured area
            accent.withAlphaComponent(0.12).setFill()
            r.fill()
            accent.setStroke()
            let p = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); p.lineWidth = 1; p.stroke()
            let w = Int(r.width), h = Int(r.height)
            label("\(w) × \(h)", sub: "@\(Int(scale))x  \(Int(r.width * scale)) × \(Int(r.height * scale))",
                  at: NSPoint(x: r.midX, y: r.minY - 8), above: false)
        }

        if let m = mouse {
            accent.withAlphaComponent(0.7).setStroke()
            let h = NSBezierPath(); h.move(to: NSPoint(x: 0, y: m.y + 0.5)); h.line(to: NSPoint(x: bounds.maxX, y: m.y + 0.5))
            let v = NSBezierPath(); v.move(to: NSPoint(x: m.x + 0.5, y: 0)); v.line(to: NSPoint(x: m.x + 0.5, y: bounds.maxY))
            h.lineWidth = 1; v.lineWidth = 1; h.stroke(); v.stroke()
            if rect == nil {
                label("\(Int(m.x)), \(Int(bounds.height - m.y))", sub: nil,
                      at: NSPoint(x: m.x + 14, y: m.y - 14), above: false, leading: true)
            }
        }

        label("Drag to measure", sub: "↩ copy   ·   esc close", at: NSPoint(x: bounds.midX, y: bounds.maxY - 60), above: false)
    }

    private func label(_ s: String, sub: String?, at p: NSPoint, above: Bool, leading: Bool = false) {
        let main: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                                                   .foregroundColor: NSColor.white]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                                                    .foregroundColor: NSColor.white.withAlphaComponent(0.8)]
        let ms = (s as NSString).size(withAttributes: main)
        let ss = sub.map { ($0 as NSString).size(withAttributes: small) } ?? .zero
        let w = max(ms.width, ss.width) + 16
        let h = ms.height + (sub == nil ? 0 : ss.height + 2) + 10
        var r = NSRect(x: leading ? p.x : p.x - w / 2, y: above ? p.y : p.y - h, width: w, height: h)
        r.origin.x = min(max(r.minX, 8), bounds.maxX - w - 8)
        r.origin.y = min(max(r.minY, 8), bounds.maxY - h - 8)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        (s as NSString).draw(at: NSPoint(x: r.minX + 8, y: r.maxY - 5 - ms.height), withAttributes: main)
        if let sub { (sub as NSString).draw(at: NSPoint(x: r.minX + 8, y: r.minY + 5), withAttributes: small) }
    }
}
