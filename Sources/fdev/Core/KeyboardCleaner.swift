import SwiftUI
import AppKit
import ApplicationServices

/// Blocks all keyboard input (keys, modifiers, media/brightness keys) so the keyboard can be wiped.
/// Unlock with the mouse — or it unlocks itself when the timer runs out.
@MainActor
final class KeyboardCleaner: ObservableObject {
    static let shared = KeyboardCleaner()

    @Published private(set) var active = false
    @Published private(set) var endsAt = Date()
    @Published var blockedCount = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var windows: [NSWindow] = []
    private var timer: Timer?

    static let duration: TimeInterval = 60

    func start() {
        guard !active else { return }
        guard AXIsProcessTrusted() else {
            FontStore.shared.requestAccess()
            CopyHUD.shared.show(text: "Allow Accessibility for fdev first", swatch: nil, symbol: "lock.shield")
            return
        }
        MenuPanel.shared.close()

        // keyDown, keyUp, flagsChanged + NX_SYSDEFINED (14: volume, brightness, play/pause…)
        let types: [UInt32] = [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
                               CGEventType.flagsChanged.rawValue, 14]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1)) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { KeyboardCleaner.shared.reenable() }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown { DispatchQueue.main.async { KeyboardCleaner.shared.blockedCount += 1 } }
            return nil                                   // swallow it
        }, userInfo: nil) else {
            CopyHUD.shared.show(text: "Couldn't lock the keyboard", swatch: nil, symbol: "exclamationmark.triangle")
            return
        }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        source = src
        CGEvent.tapEnable(tap: tap, enable: true)

        blockedCount = 0
        endsAt = Date().addingTimeInterval(Self.duration)
        active = true
        showOverlay()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                let me = KeyboardCleaner.shared
                if Date() >= me.endsAt { me.stop() }
            }
        }
    }

    func addTime(_ s: TimeInterval = 30) { endsAt = max(endsAt, Date()).addingTimeInterval(s) }

    func stop() {
        guard active else { return }
        timer?.invalidate(); timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        active = false
        CopyHUD.shared.show(text: "Keyboard unlocked", swatch: nil, symbol: "keyboard")
    }

    private func reenable() { if let tap, active { CGEvent.tapEnable(tap: tap, enable: true) } }

    private func showOverlay() {
        for screen in NSScreen.screens {
            let w = CleanerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hidesOnDeactivate = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let isMain = screen == (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)
            let container = NSView()
            let host = NSHostingView(rootView: CleanerOverlay(showControls: isMain))
            host.sizingOptions = []
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            w.contentView = container
            host.frame = container.bounds
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            if isMain { w.makeKey() }
            windows.append(w)
        }
    }
}

final class CleanerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct CleanerOverlay: View {
    let showControls: Bool
    @ObservedObject private var c = KeyboardCleaner.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            if showControls {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let left = max(0, Int(c.endsAt.timeIntervalSince(ctx.date).rounded(.up)))
                    VStack(spacing: 14) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 44, weight: .light))
                            .symbolEffect(.pulse, value: c.blockedCount)
                        Text("Keyboard locked for cleaning").font(.title2.weight(.semibold))
                        Text("Wipe away — every key is ignored. Use the mouse or trackpad to unlock.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("Unlocks automatically in \(left) s · \(c.blockedCount) key presses blocked")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("+30 s") { c.addTime() }
                                .controlSize(.large)
                            Button("Unlock Keyboard") { c.stop() }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                        }
                        .padding(.top, 6)
                    }
                    .padding(32)
                    .frame(width: 440)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}
