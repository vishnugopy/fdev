import SwiftUI
import AppKit

struct FontTool: View {
    @ObservedObject private var store = FontStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            if !store.trusted {
                PermissionCard()
            } else {
                Instructions()
                if let f = store.current {
                    ResultCard(font: f)
                    SourceCard(font: f)
                } else {
                    Placeholder()
                }
            }
            if let s = store.status, store.trusted {
                Label(s, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { store.refreshTrust() }
        .onDisappear { store.live = false }
    }
}

private struct Instructions: View {
    @ObservedObject private var store = FontStore.shared

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Keycap("⌥"); Keycap("⌘"); Keycap("F")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Option Command F")
            Text("Hover any text, press to detect & copy")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle("Live", isOn: $store.live)
                .toggleStyle(.switch).controlSize(.mini).font(.caption)
                .help("Update continuously while you hover")
        }
    }
}

private struct ResultCard: View {
    let font: DetectedFont

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(font.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .textSelection(.enabled)
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
            Text(font.sample.isEmpty ? "The quick brown fox jumps over the lazy dog" : font.sample)
                .font(previewFont)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !font.isInstalled {
                Text("Preview uses a fallback — this font isn't installed on your Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
    }

    private var meta: String {
        var parts: [String] = []
        if let s = font.size { parts.append("\(String(format: "%g", (s * 10).rounded() / 10))px") }
        if let w = font.weightName { parts.append(font.cssWeight.map { "\(w) · \($0)" } ?? w) }
        if let ps = font.postScriptName, ps != font.family { parts.append(ps) }
        if let app = font.appName { parts.append("in \(app)") }
        return parts.joined(separator: "  ·  ")
    }

    private var previewFont: Font {
        if font.isSystemUI { return .system(size: 17) }
        if let ps = font.postScriptName, NSFont(name: ps, size: 17) != nil { return .custom(ps, size: 17) }
        return .custom(font.family, size: 17)
    }
}

private struct SourceCard: View {
    @ObservedObject private var store = FontStore.shared
    let font: DetectedFont

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLine
            Group {
                HStack(spacing: 8) {
                    Button { Clipboard.copy(store.cssFontFamily, symbol: "textformat") } label: {
                        Label("Copy CSS", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    switch store.source {
                    case .google(let family, _):
                        Button {
                            Clipboard.copy(GoogleFonts.importCSS(family, weight: font.cssWeight), symbol: "link")
                        } label: { Label("Copy @import", systemImage: "link") }
                            .buttonStyle(.bordered)
                        Spacer(minLength: 0)
                        Button { NSWorkspace.shared.open(GoogleFonts.specimenURL(family)) } label: {
                            Label("Google Fonts", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.borderedProminent)
                    case .notGoogle where !font.isSystemUI, .offline:
                        Spacer(minLength: 0)
                        Button { open("https://fonts.adobe.com/search?query=") } label: {
                            Label("Adobe Fonts", systemImage: "arrow.up.right")
                        }
                        .buttonStyle(.bordered)
                        Button { open("https://www.google.com/search?q=font+") } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                    default:
                        Spacer(minLength: 0)
                    }
                }
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch store.source {
        case .checking, .none:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking Google Fonts…").font(.callout)
            }
        case .google(_, let category):
            Label {
                Text("Available on Google Fonts\(category.map { " · \($0)" } ?? "")")
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
            .font(.callout.weight(.medium))
        case .notGoogle:
            Label(font.isSystemUI ? "Apple system font — use system-ui in CSS"
                  : font.isInstalled ? "Not on Google Fonts · installed on this Mac"
                  : "Not on Google Fonts · likely Adobe Fonts, a foundry, or custom",
                  systemImage: "xmark.seal")
                .font(.callout.weight(.medium))
        case .offline:
            Label("Couldn't reach Google Fonts to check", systemImage: "wifi.exclamationmark")
                .font(.callout.weight(.medium))
        }
    }

    private func open(_ prefix: String) {
        let q = font.family.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? font.family
        if let url = URL(string: prefix + q) { NSWorkspace.shared.open(url) }
    }
}

private struct Placeholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "textformat")
                .font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No font detected yet").font(.headline)
            Text("Works on web pages in Safari, Chrome, Arc and Edge, and on text in native apps.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24).padding(.horizontal, 20)
        .well()
    }
}

private struct PermissionCard: View {
    @ObservedObject private var store = FontStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility access needed", systemImage: "lock.shield")
                .font(.headline)
            Text("fdev reads the real font name, size and weight of the text under your cursor through macOS Accessibility. Nothing leaves your Mac except the Google Fonts name check.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                HStack(spacing: 8) {
                    Button("Grant access") { store.requestAccess() }
                        .buttonStyle(.borderedProminent)
                    Button("Check again") { store.refreshTrust() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        // Flip to the detector automatically as soon as access is granted in System Settings.
        .task {
            while !Task.isCancelled && !store.trusted {
                try? await Task.sleep(for: .seconds(1))
                store.refreshTrust()
            }
        }
    }
}
