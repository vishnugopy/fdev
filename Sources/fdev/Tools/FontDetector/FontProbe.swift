import AppKit
import ApplicationServices

struct DetectedFont: Equatable {
    var family: String           // as reported, e.g. "Inter" or ".AppleSystemUIFont"
    var postScriptName: String?  // e.g. "Inter-SemiBold"
    var size: Double?
    var sample: String
    var appName: String?

    var isSystemUI: Bool { family.hasPrefix(".") || family.hasPrefix("SF Pro") || family == "-apple-system" }

    var displayName: String { isSystemUI ? "SF Pro (system-ui)" : family }

    /// Weight name parsed from the PostScript name ("Inter-SemiBold" → "SemiBold").
    var weightName: String? {
        guard let ps = postScriptName, let dash = ps.lastIndex(of: "-") else { return nil }
        let w = String(ps[ps.index(after: dash)...]).replacingOccurrences(of: "Italic", with: "")
        return w.isEmpty ? "Regular" : w
    }

    var cssWeight: Int? {
        guard let w = weightName?.lowercased() else { return nil }
        let table: [(String, Int)] = [("thin", 100), ("hairline", 100), ("extralight", 200), ("ultralight", 200),
                                      ("light", 300), ("regular", 400), ("book", 400), ("normal", 400),
                                      ("medium", 500), ("semibold", 600), ("demibold", 600),
                                      ("extrabold", 800), ("ultrabold", 800), ("bold", 700),
                                      ("black", 900), ("heavy", 900)]
        return table.first { w == $0.0 }?.1 ?? table.first { w.contains($0.0) }?.1
    }

    var isInstalled: Bool {
        isSystemUI || NSFontManager.shared.availableFontFamilies.contains(family)
            || (postScriptName.flatMap { NSFont(name: $0, size: 12) } != nil)
    }

    func sameFont(as o: DetectedFont) -> Bool {
        family == o.family && postScriptName == o.postScriptName && size == o.size
    }
}

/// Reads the real font of text under the cursor through the macOS Accessibility API.
/// Works for native apps and web content in Safari, Chrome, Arc, Edge, Electron apps…
enum FontProbe {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Mouse location in AX (top-left origin) coordinates. Call on the main thread.
    @MainActor static func mousePoint() -> CGPoint {
        let m = NSEvent.mouseLocation
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: m.x, y: h - m.y)
    }

    private static var chromiumEnabled = Set<pid_t>()  // only touched on the probe queue

    /// Call from a background serial queue.
    static func probe(at p: CGPoint) -> DetectedFont? {
        let sys = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 0.4)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(p.x), Float(p.y), &hit) == .success,
              let el = hit else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        if pid == getpid() { return nil }   // ignore our own panel
        enableChromiumAccessibility(pid)
        AXUIElementSetMessagingTimeout(el, 0.4)

        guard let attributed = webAttributedString(el) ?? nativeAttributedString(el, at: p),
              var font = parse(attributed) else { return nil }
        font.appName = NSRunningApplication(processIdentifier: pid)?.localizedName
        return font
    }

    // MARK: Web content (WebKit / Chromium text markers)

    private static func webAttributedString(_ el: AXUIElement) -> NSAttributedString? {
        // The text marker APIs are answered by the element itself or its web area.
        for receiver in [el, ancestor(of: el, role: "AXWebArea")].compactMap({ $0 }) {
            guard let range = param(receiver, "AXTextMarkerRangeForUIElement", el),
                  let s = attributed(param(receiver, "AXAttributedStringForTextMarkerRange", range))
            else { continue }
            if s.length > 0 { return s }
        }
        return nil
    }

    // MARK: Native text (NSTextView, labels, fields…)

    private static func nativeAttributedString(_ el: AXUIElement, at p: CGPoint) -> NSAttributedString? {
        var count: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXNumberOfCharactersAttribute as CFString, &count)
        let total = (count as? Int) ?? 0
        guard total > 0 else { return nil }

        var location = 0
        var point = p
        if let pv = AXValueCreate(.cgPoint, &point),
           let r = param(el, kAXRangeForPositionParameterizedAttribute, pv) {
            var cf = CFRange()
            if AXValueGetValue(r as! AXValue, .cfRange, &cf) { location = cf.location }
        }
        let start = max(0, min(location, total - 1))
        var range = CFRange(location: start, length: min(60, total - start))
        guard let rv = AXValueCreate(.cfRange, &range) else { return nil }
        return attributed(param(el, kAXAttributedStringForRangeParameterizedAttribute, rv))
    }

    // MARK: Parsing

    private static func parse(_ s: NSAttributedString) -> DetectedFont? {
        let ns = s.string as NSString
        let first = ns.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted)
        guard first.location != NSNotFound else { return nil }
        let attrs = s.attributes(at: first.location, effectiveRange: nil)

        var family: String?, ps: String?, size: Double?
        if let d = attrs[NSAttributedString.Key("AXFont")] as? [String: Any] {
            family = d["AXFontFamily"] as? String
            ps = d["AXFontName"] as? String
            size = (d["AXFontSize"] as? NSNumber)?.doubleValue
        } else if let f = attrs[.font] as? NSFont {
            family = f.familyName; ps = f.fontName; size = Double(f.pointSize)
        }
        guard let family, !family.isEmpty else { return nil }
        let sample = s.string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return DetectedFont(family: family, postScriptName: ps, size: size,
                            sample: String(sample.prefix(90)), appName: nil)
    }

    // MARK: Helpers

    /// Chromium (Chrome, Arc, Edge, Electron) only builds its accessibility tree when asked.
    private static func enableChromiumAccessibility(_ pid: pid_t) {
        guard !chromiumEnabled.contains(pid) else { return }
        chromiumEnabled.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func ancestor(of el: AXUIElement, role: String) -> AXUIElement? {
        var cur: AXUIElement? = el
        for _ in 0..<25 {
            guard let c = cur else { return nil }
            var r: CFTypeRef?
            AXUIElementCopyAttributeValue(c, kAXRoleAttribute as CFString, &r)
            if (r as? String) == role { return c }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(c, kAXParentAttribute as CFString, &parent) == .success,
                  let p = parent, CFGetTypeID(p) == AXUIElementGetTypeID() else { return nil }
            cur = (p as! AXUIElement)
        }
        return nil
    }

    private static func param(_ el: AXUIElement, _ attr: String, _ arg: CFTypeRef) -> CFTypeRef? {
        var out: CFTypeRef?
        return AXUIElementCopyParameterizedAttributeValue(el, attr as CFString, arg, &out) == .success ? out : nil
    }

    private static func attributed(_ v: CFTypeRef?) -> NSAttributedString? {
        guard let v, CFGetTypeID(v) == CFAttributedStringGetTypeID() else { return nil }
        return (v as! CFAttributedString) as NSAttributedString
    }
}
