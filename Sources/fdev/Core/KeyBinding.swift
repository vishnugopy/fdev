import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A user-configurable global shortcut.
struct KeyBinding: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int        // Carbon mask: cmdKey | optionKey | controlKey | shiftKey
    var keys: [String]        // for display, e.g. ["⌥", "⌘", "C"]

    var display: String { keys.joined() }

    static let functionKeys: Set<Int> = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9,
                                         kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16,
                                         kVK_F17, kVK_F18, kVK_F19, kVK_F20]

    /// Ready-made choices for the action wheel (shown as a menu in Settings › Wheel).
    static let wheelPresets: [KeyBinding] = [
        KeyBinding(keyCode: kVK_Space, modifiers: optionKey, keys: ["⌥", "Space"]),
        KeyBinding(keyCode: kVK_Tab, modifiers: optionKey, keys: ["⌥", "Tab"]),
        KeyBinding(keyCode: kVK_Space, modifiers: controlKey | optionKey, keys: ["⌃", "⌥", "Space"]),
        KeyBinding(keyCode: kVK_ANSI_W, modifiers: optionKey | cmdKey, keys: ["⌥", "⌘", "W"]),
        KeyBinding(keyCode: kVK_F13, modifiers: 0, keys: ["F13"]),
    ]

    static func from(_ e: NSEvent) -> KeyBinding? {
        let f = e.modifierFlags
        // Function keys may be used alone; anything else needs ⌘, ⌥ or ⌃ so normal typing isn't hijacked.
        guard f.contains(.command) || f.contains(.option) || f.contains(.control)
                || functionKeys.contains(Int(e.keyCode)) else { return nil }
        var mods = 0, keys: [String] = []
        if f.contains(.control) { mods |= controlKey; keys.append("⌃") }
        if f.contains(.option) { mods |= optionKey; keys.append("⌥") }
        if f.contains(.shift) { mods |= shiftKey; keys.append("⇧") }
        if f.contains(.command) { mods |= cmdKey; keys.append("⌘") }
        keys.append(keyName(Int(e.keyCode), fallback: e.charactersIgnoringModifiers))
        return KeyBinding(keyCode: Int(e.keyCode), modifiers: mods, keys: keys)
    }

    static func keyName(_ code: Int, fallback: String?) -> String {
        let named: [Int: String] = [
            kVK_Tab: "Tab", kVK_Space: "Space", kVK_Return: "↩", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_Grave: "`",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
            kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let n = named[code] { return n }
        let s = (fallback ?? "?").uppercased()
        return s.isEmpty ? "?" : s
    }
}

/// "Change" → press a combo → saved. Esc cancels. Global hotkeys are paused while recording
/// so the combo you press isn't swallowed by an existing shortcut.
struct ShortcutRecorder: View {
    let shortcut: Shortcut
    @ObservedObject private var s = AppSettings.shared
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 8) {
                if recording {
                    Text("Press keys…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8).frame(minHeight: 22)
                        .chip(true)
                } else {
                    HStack(spacing: 3) { ForEach(s.binding(for: shortcut).keys, id: \.self) { Keycap($0) } }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(s.binding(for: shortcut).display)
                }
                Button(recording ? "Cancel" : "Change") { recording ? stop() : start() }
                if s.isCustom(shortcut) && !recording {
                    Button { s.setBinding(nil, for: shortcut) } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .help("Reset to \(shortcut.defaultBinding.display)")
                        .accessibilityLabel("Reset to default")
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        message = nil
        recording = true
        HotKey.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            guard let b = KeyBinding.from(e) else {
                message = "Include ⌘, ⌥ or ⌃ (or use an F‑key)."
                NSSound.beep()
                return nil
            }
            if let clash = s.conflict(b, excluding: shortcut) {
                message = "Already used by “\(clash.title)”."
                NSSound.beep()
                return nil
            }
            s.setBinding(b, for: shortcut)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false }
        s.applyHotKeys()
    }
}
