import SwiftUI
import AppKit

struct PickedColor: Codable, Identifiable, Equatable {
    var id = UUID()
    /// sRGB components, 0...1
    var r: Double, g: Double, b: Double, a: Double
    /// Display P3 components, 0...1
    var p3r: Double, p3g: Double, p3b: Double
    var date = Date()

    init?(_ ns: NSColor) {
        guard let s = ns.usingColorSpace(.sRGB) else { return nil }
        r = Self.clamp(s.redComponent); g = Self.clamp(s.greenComponent)
        b = Self.clamp(s.blueComponent); a = Self.clamp(s.alphaComponent)
        let p = ns.usingColorSpace(.displayP3) ?? s
        p3r = Self.clamp(p.redComponent); p3g = Self.clamp(p.greenComponent); p3b = Self.clamp(p.blueComponent)
    }

    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                          blue: CGFloat(v & 0xFF) / 255, alpha: 1))
    }

    private static func clamp(_ v: CGFloat) -> Double { min(max(Double(v), 0), 1) }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var r8: Int { Int((r * 255).rounded()) }
    var g8: Int { Int((g * 255).rounded()) }
    var b8: Int { Int((b * 255).rounded()) }

    var hex: String { String(format: "#%02X%02X%02X", r8, g8, b8) }
    /// HEX as written to CSS — respects the "lowercase HEX" setting.
    var cssHex: String { UserDefaults.standard.bool(forKey: "color.hexLowercase") ? hex.lowercased() : hex }

    var hsl: (h: Int, s: Int, l: Int) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let l = (mx + mn) / 2
        var h = 0.0, s = 0.0
        if d > 0 {
            s = d / (1 - abs(2 * l - 1))
            switch mx {
            case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
            case g: h = (b - r) / d + 2
            default: h = (r - g) / d + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (Int(h.rounded()) % 360, Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    /// Relative luminance (WCAG) — used for text contrast on the swatch.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
    var isLight: Bool { luminance > 0.4 }

    func contrast(with other: Double) -> Double {
        let (l1, l2) = (max(luminance, other), min(luminance, other))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    var cssVarName: String { "--color-\(hex.dropFirst().lowercased())" }

    func string(_ f: ColorFormat) -> String {
        let f3 = { (v: Double) in String(format: "%.3f", v) }
        switch f {
        case .hex: return cssHex
        case .rgb: return "rgb(\(r8) \(g8) \(b8))"
        case .hsl: let h = hsl; return "hsl(\(h.h) \(h.s)% \(h.l)%)"
        case .p3: return "color(display-p3 \(f3(p3r)) \(f3(p3g)) \(f3(p3b)))"
        case .swiftUI: return "Color(red: \(f3(r)), green: \(f3(g)), blue: \(f3(b)))"
        case .cssVar: return "\(cssVarName): \(cssHex);"
        }
    }
}

enum ColorFormat: String, CaseIterable, Identifiable {
    case hex = "HEX", rgb = "RGB", hsl = "HSL", p3 = "P3", swiftUI = "SwiftUI", cssVar = "CSS Var"
    var id: String { rawValue }
}

@MainActor
final class ColorStore: ObservableObject {
    static let shared = ColorStore()

    @Published var history: [PickedColor] = []
    @Published var selected: PickedColor?
    @Published var autoCopy: Bool = UserDefaults.standard.object(forKey: "color.autoCopy") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCopy, forKey: "color.autoCopy") }
    }
    @Published var autoCopyFormat: ColorFormat =
        ColorFormat(rawValue: UserDefaults.standard.string(forKey: "color.autoCopyFormat") ?? "") ?? .hex {
        didSet { UserDefaults.standard.set(autoCopyFormat.rawValue, forKey: "color.autoCopyFormat") }
    }

    private let key = "colorHistory.v1"
    private let maxHistory = 40
    private var sampler: NSColorSampler?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([PickedColor].self, from: data) {
            history = saved
            selected = saved.first
        }
    }

    /// Opens the system magnifier loupe — works across every window and display.
    /// NSColorSampler needs no Screen Recording permission.
    func sample(_ done: @escaping (PickedColor) -> Void) {
        // Close the menu-bar panel so it's out of the way (leave the full window alone).
        MenuPanel.shared.close()
        let s = NSColorSampler()
        sampler = s
        s.show { [weak self] ns in
            Task { @MainActor in
                self?.sampler = nil
                if let ns, let c = PickedColor(ns) { done(c) }
            }
        }
    }

    func pick() {
        sample { c in
            self.add(c)
            if self.autoCopy { self.copy(c, as: self.autoCopyFormat) }
        }
    }

    func copy(_ c: PickedColor, as f: ColorFormat) {
        Clipboard.copy(c.string(f), swatch: c.color)
    }

    func add(_ c: PickedColor) {
        history.removeAll { $0.hex == c.hex }
        history.insert(c, at: 0)
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        selected = c
        save()
    }

    func remove(_ c: PickedColor) {
        history.removeAll { $0.id == c.id }
        if selected?.id == c.id { selected = history.first }
        save()
    }

    func clear() { history = []; selected = nil; save() }

    /// All history as CSS custom properties — paste straight into your stylesheet.
    func copyPalette() {
        let body = history.map { "  \($0.string(.cssVar))" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(":root {\n\(body)\n}", forType: .string)
        CopyHUD.shared.show(text: "\(history.count) colors as CSS", swatch: nil, symbol: "paintpalette")
    }

    /// Re-read after an iCloud sync.
    func reload() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: key), let saved = try? JSONDecoder().decode([PickedColor].self, from: data) {
            history = saved
            if let sel = selected, !saved.contains(where: { $0.id == sel.id }) { selected = saved.first }
        }
        if let a = d.object(forKey: "color.autoCopy") as? Bool, a != autoCopy { autoCopy = a }
        if let f = ColorFormat(rawValue: d.string(forKey: "color.autoCopyFormat") ?? ""), f != autoCopyFormat { autoCopyFormat = f }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
