import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

enum ToastPosition: String, CaseIterable, Identifiable {
    case top = "Top", center = "Center", bottom = "Bottom"
    var id: String { rawValue }
}

struct Shortcut: Identifiable {
    let id: UInt32
    let title: String
    let defaultBinding: KeyBinding
    let onPress: @MainActor () -> Void
    var onRelease: (@MainActor () -> Void)? = nil

    static let wheelID: UInt32 = 4

    static let all: [Shortcut] = [
        Shortcut(id: wheelID, title: "Action wheel",
                 defaultBinding: KeyBinding(keyCode: kVK_Space, modifiers: optionKey, keys: ["⌥", "Space"]),
                 onPress: { ActionWheel.shared.keyDown() }, onRelease: { ActionWheel.shared.keyUp() }),
        Shortcut(id: 1, title: "Pick a color",
                 defaultBinding: KeyBinding(keyCode: kVK_ANSI_C, modifiers: cmdKey | optionKey, keys: ["⌥", "⌘", "C"]),
                 onPress: { ColorStore.shared.pick() }),
        Shortcut(id: 2, title: "Detect font",
                 defaultBinding: KeyBinding(keyCode: kVK_ANSI_F, modifiers: cmdKey | optionKey, keys: ["⌥", "⌘", "F"]),
                 onPress: { FontStore.shared.detect(copy: true) }),
        Shortcut(id: 3, title: "Measure screen",
                 defaultBinding: KeyBinding(keyCode: kVK_ANSI_M, modifiers: cmdKey | optionKey, keys: ["⌥", "⌘", "M"]),
                 onPress: { ScreenRuler.shared.start() }),
    ]
}

/// App-wide preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var toastEnabled: Bool = true { didSet { d.set(toastEnabled, forKey: "toast.enabled") } }
    @Published var toastDuration: Double = 1.0 { didSet { d.set(toastDuration, forKey: "toast.duration") } }
    @Published var toastPosition: ToastPosition = .center { didSet { d.set(toastPosition.rawValue, forKey: "toast.position") } }
    @Published var hexLowercase: Bool = false { didSet { d.set(hexLowercase, forKey: "color.hexLowercase") } }
    @Published var hiddenTools: Set<String> = [] { didSet { d.set(Array(hiddenTools), forKey: "tools.hidden") } }
    @Published var disabledShortcuts: Set<UInt32> = [] {
        didSet { d.set(disabledShortcuts.map(Int.init), forKey: "shortcuts.disabled"); applyHotKeys() }
    }
    @Published var customBindings: [UInt32: KeyBinding] = [:] {
        didSet {
            let enc = Dictionary(uniqueKeysWithValues: customBindings.map { (String($0.key), $0.value) })
            d.set(try? JSONEncoder().encode(enc), forKey: "shortcuts.custom")
        }
    }
    /// Tools on the action wheel, in order (clockwise from the top).
    @Published var wheelTools: [Tool] = AppSettings.defaultWheel { didSet { d.set(wheelTools.map(\.rawValue), forKey: "wheel.tools") } }
    /// Hold the shortcut, point, release to select. Off = press to open, click to select.
    @Published var wheelHold: Bool = true { didSet { d.set(wheelHold, forKey: "wheel.hold") } }
    static let defaultWheel: [Tool] = [.color, .font, .measure, .contrast, .units, .shadow, .image, .text]
    /// Live diagnostics for Settings › Shortcuts.
    @Published var lastHotKey: (id: UInt32, pressed: Bool, at: Date)?
    @Published var failedShortcuts: Set<UInt32> = []
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?

    init() { load() }

    /// (Re)reads everything from UserDefaults — also called after an iCloud sync.
    func load() {
        toastEnabled = d.object(forKey: "toast.enabled") as? Bool ?? true
        toastDuration = d.object(forKey: "toast.duration") as? Double ?? 1.0
        toastPosition = ToastPosition(rawValue: d.string(forKey: "toast.position") ?? "") ?? .center
        hexLowercase = d.bool(forKey: "color.hexLowercase")
        hiddenTools = Set(d.stringArray(forKey: "tools.hidden") ?? [])
        disabledShortcuts = Set((d.array(forKey: "shortcuts.disabled") as? [Int] ?? []).map(UInt32.init))
        if let data = d.data(forKey: "shortcuts.custom"),
           let dec = try? JSONDecoder().decode([String: KeyBinding].self, from: data) {
            customBindings = Dictionary(uniqueKeysWithValues: dec.compactMap { k, v in UInt32(k).map { ($0, v) } })
        } else {
            customBindings = [:]
        }
        let saved = (d.stringArray(forKey: "wheel.tools") ?? []).compactMap(Tool.init(rawValue:))
        wheelTools = saved.count >= 2 ? saved : Self.defaultWheel
        wheelHold = d.object(forKey: "wheel.hold") as? Bool ?? true
    }

    func binding(for sc: Shortcut) -> KeyBinding { customBindings[sc.id] ?? sc.defaultBinding }
    func isCustom(_ sc: Shortcut) -> Bool { customBindings[sc.id] != nil }

    func setBinding(_ b: KeyBinding?, for sc: Shortcut) {
        customBindings[sc.id] = b
        applyHotKeys()
    }

    func conflict(_ b: KeyBinding, excluding sc: Shortcut) -> Shortcut? {
        Shortcut.all.first { $0.id != sc.id && binding(for: $0).keyCode == b.keyCode && binding(for: $0).modifiers == b.modifiers }
    }

    func setWheel(_ t: Tool, included: Bool) {
        if included { if !wheelTools.contains(t) { wheelTools = Tool.allCases.filter { wheelTools.contains($0) || $0 == t } } }
        else if wheelTools.count > 2 { wheelTools.removeAll { $0 == t } }
    }

    var visibleTools: [Tool] {
        let v = Tool.allCases.filter { !hiddenTools.contains($0.rawValue) }
        return v.isEmpty ? [.color] : v
    }

    func setTool(_ t: Tool, visible: Bool) {
        if visible { hiddenTools.remove(t.rawValue) }
        else if visibleTools.count > 1 { hiddenTools.insert(t.rawValue) }
    }

    func applyHotKeys() {
        HotKey.shared.onEvent = { id, pressed in
            Task { @MainActor in AppSettings.shared.lastHotKey = (id, pressed, Date()) }
        }
        var failed: Set<UInt32> = []
        defer { if failed != failedShortcuts { failedShortcuts = failed } }
        for sc in Shortcut.all {
            if disabledShortcuts.contains(sc.id) {
                HotKey.shared.unregister(id: sc.id)
                continue
            }
            let b = binding(for: sc)
            let press = sc.onPress, release = sc.onRelease
            let ok = HotKey.shared.register(id: sc.id, key: b.keyCode, modifiers: b.modifiers,
                                   onPress: { Task { @MainActor in press() } },
                                   onRelease: release.map { r in { Task { @MainActor in r() } } })
            if !ok { failed.insert(sc.id) }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription). Try moving fdev to /Applications."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func resetAll() {
        if let id = Bundle.main.bundleIdentifier { d.removePersistentDomain(forName: id) }
        toastEnabled = true; toastDuration = 1.0; toastPosition = .center
        hexLowercase = false; hiddenTools = []; disabledShortcuts = []
        customBindings = [:]; wheelTools = Self.defaultWheel; wheelHold = true
    }

    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }
}
