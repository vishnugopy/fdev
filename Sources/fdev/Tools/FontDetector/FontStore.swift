import AppKit
import SwiftUI

@MainActor
final class FontStore: ObservableObject {
    static let shared = FontStore()

    enum Source: Equatable {
        case checking
        case google(family: String, category: String?)
        case notGoogle
        case offline
    }

    @Published var current: DetectedFont?
    @Published var source: Source?
    @Published var status: String?
    @Published var trusted = FontProbe.isTrusted
    @Published var live = false {
        didSet { live ? startLive() : stopLive() }
    }

    private let queue = DispatchQueue(label: "local.fdev.fontprobe", qos: .userInitiated)
    private var timer: Timer?
    private var inFlight = false

    /// Detect the font under the cursor. With `copy`, also copies the CSS font-family (⌥⌘F).
    func detect(copy: Bool = false, at point: CGPoint? = nil) {
        trusted = FontProbe.isTrusted
        guard trusted else {
            if copy { FontProbe.requestTrust() }
            status = "fdev needs Accessibility access to read fonts."
            return
        }
        guard !inFlight else { return }
        inFlight = true
        let point = point ?? FontProbe.mousePoint()
        queue.async {
            let result = FontProbe.probe(at: point)
            DispatchQueue.main.async { self.apply(result, copy: copy) }
        }
    }

    private func apply(_ r: DetectedFont?, copy: Bool) {
        inFlight = false
        guard let r else {
            if !live {
                status = "No readable text under the cursor. Hover text, then press ⌥⌘F."
                if copy { CopyHUD.shared.show(text: "No text found", swatch: nil, symbol: "textformat") }
            }
            return
        }
        status = nil
        let changed = current.map { !$0.sameFont(as: r) } ?? true
        current = r
        if changed { checkSource(r) }
        if copy { Clipboard.copy(r.displayName, symbol: "textformat") }
    }

    private func checkSource(_ f: DetectedFont) {
        if f.isSystemUI { source = .notGoogle; return }
        source = .checking
        Task {
            do {
                let hit = try await GoogleFonts.shared.match(f)
                guard current?.sameFont(as: f) == true else { return }
                source = hit.map { .google(family: $0.family, category: $0.category) } ?? .notGoogle
            } catch {
                guard current?.sameFont(as: f) == true else { return }
                source = .offline
            }
        }
    }

    var cssFontFamily: String {
        guard let f = current else { return "" }
        if f.isSystemUI { return "font-family: system-ui, -apple-system, sans-serif;" }
        var category: String?
        if case .google(_, let c) = source { category = c }
        let name = f.family.contains(" ") ? "\"\(f.family)\"" : f.family
        return "font-family: \(name), \(GoogleFonts.generic(for: category));"
    }

    func requestAccess() {
        FontProbe.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshTrust() { trusted = FontProbe.isTrusted; if trusted { status = nil } }

    private func startLive() {
        stopLive()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            Task { @MainActor in self.detect() }
        }
    }

    private func stopLive() { timer?.invalidate(); timer = nil }
}
