import SwiftUI
import AppKit
import Carbon.HIToolbox

/// GTA-style radial menu.
/// Hold the shortcut → wheel opens around the cursor → point at a slice → release to run it.
/// Quick tap instead → wheel stays open: click a slice, press 1–9, Return, or Esc to close.
@MainActor
final class ActionWheel {
    static let shared = ActionWheel()

    final class Model: ObservableObject {
        @Published var items: [Tool] = []
        @Published var highlighted: Int?
        @Published var origin: CGPoint = .zero   // wheel center in view coordinates (top-left origin)
        @Published var appeared = false
    }

    let model = Model()
    private var panel: WheelPanel?
    private var timer: Timer?
    private var center: NSPoint = .zero          // wheel center in screen coordinates (may be nudged on-screen)
    private var anchor: NSPoint = .zero          // where the cursor was when the wheel opened — aiming is relative to this
    private var keyHeld = false                  // true between hotkey press and release

    static let outer: CGFloat = 150
    static let inner: CGFloat = 58

    var isOpen: Bool { panel?.isVisible == true }

    // MARK: Hotkey

    private var lastPress = Date.distantPast
    private var sawPhysicalDown = false

    /// Best-effort physical key state. Without Input Monitoring permission macOS may always answer
    /// "not down", so this is only trusted after it has reported "down" at least once.
    private func physicallyDown() -> Bool {
        guard let sc = Shortcut.all.first(where: { $0.id == Shortcut.wheelID }) else { return false }
        let b = AppSettings.shared.binding(for: sc)
        let keyDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(b.keyCode))
        if b.modifiers == 0 { return keyDown }
        let f = NSEvent.modifierFlags
        var held = true
        if b.modifiers & optionKey != 0 { held = held && f.contains(.option) }
        if b.modifiers & cmdKey != 0 { held = held && f.contains(.command) }
        if b.modifiers & controlKey != 0 { held = held && f.contains(.control) }
        if b.modifiers & shiftKey != 0 { held = held && f.contains(.shift) }
        return held || keyDown
    }

    func keyDown() {
        let now = Date()
        defer { lastPress = now }
        if isOpen {
            // While the key is held, macOS keeps sending "pressed" (auto-repeat) — never treat that as a choice.
            if keyHeld { return }
            commit()                         // tap mode: a second, deliberate press confirms
            return
        }
        keyHeld = true
        sawPhysicalDown = false
        open()
    }

    func keyUp() {
        guard keyHeld else { return }
        keyHeld = false
        guard isOpen, AppSettings.shared.wheelHold else { return }
        // Released without aiming: keep the wheel open so you can click, press 1–9, or Esc.
        guard model.highlighted != nil else { return }
        commit()
    }

    // MARK: Open / close

    func open() {
        let items = AppSettings.shared.wheelTools
        guard items.count >= 2 else { return }
        MenuPanel.shared.close()

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let f = screen.frame
        let margin = Self.outer + 16
        anchor = mouse
        center = NSPoint(x: min(max(mouse.x, f.minX + margin), f.maxX - margin),
                         y: min(max(mouse.y, f.minY + margin), f.maxY - margin))

        model.items = items
        model.highlighted = nil
        model.origin = CGPoint(x: center.x - f.minX, y: f.maxY - center.y)
        model.appeared = false

        let p = panel ?? makePanel()
        p.setFrame(f, display: false)
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        withAnimation(.spring(duration: 0.22)) { model.appeared = true }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
            Task { @MainActor in ActionWheel.shared.track() }
        }
    }

    func close() {
        timer?.invalidate(); timer = nil
        model.highlighted = nil
        panel?.orderOut(nil)
    }

    func commit() {
        let choice = model.highlighted.map { model.items[$0] }
        let at = anchor
        close()
        if let choice { perform(choice, at: at) }
    }

    func releaseFromPanel(keyCode: Int) {
        guard let sc = Shortcut.all.first(where: { $0.id == Shortcut.wheelID }),
              AppSettings.shared.binding(for: sc).keyCode == keyCode else { return }
        keyUp()
    }

    func select(index: Int) {
        guard model.items.indices.contains(index) else { return }
        model.highlighted = index
        commit()
    }

    // MARK: Aiming

    private func track() {
        guard isOpen else { return }
        if keyHeld {
            if physicallyDown() { sawPhysicalDown = true }
            else if sawPhysicalDown { keyUp(); if !isOpen { return } }
        }
        let m = NSEvent.mouseLocation
        // Direction from where the cursor started, not from the (possibly nudged) wheel center,
        // so nothing is highlighted until you actually move.
        let dx = m.x - anchor.x, dy = m.y - anchor.y
        guard hypot(dx, dy) > 30 else {
            if model.highlighted != nil { model.highlighted = nil }
            return
        }
        var angle = atan2(dx, dy)                    // 0 = up, clockwise
        if angle < 0 { angle += 2 * .pi }
        let slice = 2 * .pi / Double(model.items.count)
        let i = Int((angle + slice / 2) / slice) % model.items.count
        if model.highlighted != i {
            model.highlighted = i
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    // MARK: Actions

    private func perform(_ t: Tool, at point: NSPoint) {
        UserDefaults.standard.set(t.rawValue, forKey: "lastTool")
        switch t {
        case .color: ColorStore.shared.pick()
        case .measure: ScreenRuler.shared.start()
        case .font:
            // Detect at the wheel's center: that's where the cursor was when you opened it.
            let h = NSScreen.screens.first?.frame.height ?? 0
            FontStore.shared.detect(copy: true, at: CGPoint(x: point.x, y: h - point.y))
        default:
            MainWindow.shared.show(tool: t)
        }
    }

    private func makePanel() -> WheelPanel {
        let p = WheelPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.becomesKeyOnlyIfNeeded = false
        p.hidesOnDeactivate = false          // fdev stays inactive while the wheel is up — keep it visible
        // When an NSHostingView is a window's contentView, SwiftUI resizes the window to the view's
        // ideal size — 0×0 for a full-screen overlay — and the wheel vanished. Host it inside a plain
        // container instead, so the panel keeps the screen-sized frame we give it.
        let host = NSHostingView(rootView: WheelView(model: model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        let container = NSView()
        container.addSubview(host)
        p.contentView = container
        host.frame = container.bounds
        panel = p
        return p
    }
}

/// Becomes key without activating fdev, so the app you were in keeps focus.
final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func keyDown(with e: NSEvent) {
        let wheel = ActionWheel.shared
        switch Int(e.keyCode) {
        case 53: Task { @MainActor in wheel.close() }                       // Esc
        case 36, 76: Task { @MainActor in wheel.commit() }                   // Return
        default:
            if let c = e.charactersIgnoringModifiers, let n = Int(c), (1...9).contains(n) {
                Task { @MainActor in wheel.select(index: n - 1) }
            } else {
                super.keyDown(with: e)
            }
        }
    }

    override func keyUp(with e: NSEvent) {
        // While the panel is key, the key release arrives here rather than as a hotkey release.
        Task { @MainActor in ActionWheel.shared.releaseFromPanel(keyCode: Int(e.keyCode)) }
    }

    override func mouseDown(with e: NSEvent) {
        Task { @MainActor in ActionWheel.shared.commit() }   // click: run highlighted, or close if none
    }
    override func rightMouseDown(with e: NSEvent) {
        Task { @MainActor in ActionWheel.shared.close() }
    }
}

// MARK: - View

struct WheelView: View {
    @ObservedObject var model: ActionWheel.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let outer = ActionWheel.outer
    private let inner = ActionWheel.inner

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(model.appeared ? 0.06 : 0)        // barely-there dim, keeps focus on the wheel
            wheel
                .frame(width: outer * 2, height: outer * 2)
                .scaleEffect(model.appeared || reduceMotion ? 1 : 0.85)
                .opacity(model.appeared ? 1 : 0)
                .position(model.origin)
        }
        .ignoresSafeArea()
    }

    /// Liquid Glass disc styled like the Wi‑Fi menu: round icon badges (blue when chosen),
    /// a soft row-style highlight, and a section header in the middle. Follows light/dark mode.
    private var wheel: some View {
        let n = model.items.count
        return ZStack {
            Color.clear
                .glassEffect(.regular, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

            // Hairline ring between the slices and the center, like the menu's dividers.
            Circle()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                .frame(width: inner * 2, height: inner * 2)

            ForEach(0..<n, id: \.self) { i in
                let on = model.highlighted == i
                SliceShape(index: i, count: n, inner: inner + 4, outer: outer - 6)
                    .fill(Color.primary.opacity(on ? 0.1 : 0))           // same as a hovered menu row
                    .animation(.easeOut(duration: 0.12), value: on)

                let p = point(index: i, count: n, radius: (inner + outer) / 2 + 2)
                VStack(spacing: 4) {
                    IconCircle(symbol: model.items[i].icon, active: on, size: on ? 38 : 34)
                    Text("\(i + 1)")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .position(p)
                .animation(.spring(duration: 0.2), value: on)
            }

            // Center: header like the Wi‑Fi menu's "Wi‑Fi" title + secondary line.
            VStack(spacing: 2) {
                if let i = model.highlighted {
                    Text(model.items[i].title)
                        .font(.system(size: 12, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    Text("Release to run")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    LogoMark(size: 24)
                    Text("fdev").font(.system(size: 12, weight: .bold))
                    Text("Point at a tool")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(width: inner * 2 - 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.highlighted.map { "Action wheel: \(model.items[$0].title)" } ?? "Action wheel")
    }

    private func point(index i: Int, count n: Int, radius r: CGFloat) -> CGPoint {
        let a = Double(i) * 2 * .pi / Double(n)
        return CGPoint(x: outer + r * sin(a), y: outer - r * cos(a))
    }
}

/// A ring segment centered on slice `index`, starting at 12 o'clock and going clockwise.
struct SliceShape: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let span = 2 * Double.pi / Double(count)
        let gap = 0.035
        let start = Double(index) * span - span / 2 + gap
        let end = start + span - 2 * gap
        func pt(_ r: CGFloat, _ a: Double) -> CGPoint { CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)) }
        var p = Path()
        let steps = 24
        p.move(to: pt(outer, start))
        for s in 1...steps { p.addLine(to: pt(outer, start + (end - start) * Double(s) / Double(steps))) }
        for s in stride(from: steps, through: 0, by: -1) {
            p.addLine(to: pt(inner, start + (end - start) * Double(s) / Double(steps)))
        }
        p.closeSubpath()
        return p
    }
}
