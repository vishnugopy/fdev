import SwiftUI

/// WCAG 2.2 contrast checker — type HEX or sample both colors from the screen.
struct ContrastTool: View {
    @AppStorage("contrast.fg") private var fgHex = "#1F2937"
    @AppStorage("contrast.bg") private var bgHex = "#FFFFFF"

    private var fg: PickedColor? { PickedColor(hex: fgHex) }
    private var bg: PickedColor? { PickedColor(hex: bgHex) }
    private var ratio: Double? {
        guard let fg, let bg else { return nil }
        return fg.contrast(with: bg.luminance)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            preview
            if let r = ratio { results(r) }
            VStack(spacing: 8) {
                ColorInputRow(label: "Text", hex: $fgHex)
                HStack {
                    Spacer()
                    Button {
                        (fgHex, bgHex) = (bgHex, fgHex)
                    } label: { Label("Swap", systemImage: "arrow.up.arrow.down") }
                        .buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                }
                ColorInputRow(label: "Background", hex: $bgHex)
            }
        }
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Large text 24px").font(.system(size: 24, weight: .bold))
            Text("Body text at 14px — the quick brown fox jumps over the lazy dog.")
                .font(.system(size: 14))
        }
        .foregroundStyle(fg?.color ?? .primary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(bg?.color ?? .clear))
        .overlay(shape.strokeBorder(.primary.opacity(0.2), lineWidth: 1))
    }

    private func results(_ r: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(String(format: "%.2f", r)):1")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                Spacer()
                Button {
                    Clipboard.copy("\(String(format: "%.2f", r)):1")
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Copy ratio").accessibilityLabel("Copy ratio")
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Check(title: "Normal AA", needed: 4.5, ratio: r)
                    Check(title: "Normal AAA", needed: 7, ratio: r)
                }
                GridRow {
                    Check(title: "Large AA", needed: 3, ratio: r)
                    Check(title: "Large AAA", needed: 4.5, ratio: r)
                }
                GridRow {
                    Check(title: "UI & icons", needed: 3, ratio: r)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
    }
}

private struct Check: View {
    let title: String
    let needed: Double
    let ratio: Double
    var pass: Bool { ratio >= needed }

    var body: some View {
        // Icon shape + word, not color alone.
        Label {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(title) \(pass ? "Pass" : "Fail")").font(.callout)
                Text("≥\(Num.fmt(needed, decimals: 1))").font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(pass ? .green : .red)
        }
    }
}

private struct ColorInputRow: View {
    let label: String
    @Binding var hex: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var valid: Bool { PickedColor(hex: text) != nil }

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.callout).frame(width: 84, alignment: .leading)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(PickedColor(hex: hex)?.color ?? .clear)
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.primary.opacity(0.2), lineWidth: 1))
                .accessibilityHidden(true)
            TextField("#RRGGBB", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($focused)
                .accessibilityLabel("\(label) color HEX")
                .onChange(of: text) { _, t in
                    if let c = PickedColor(hex: t) { hex = c.hex }
                }
                .onChange(of: hex) { _, h in if !focused { text = h } }
                .onAppear { text = hex }
            if !valid && !text.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("Use #RGB or #RRGGBB").accessibilityLabel("Invalid HEX")
            }
            Button {
                ColorStore.shared.sample { c in hex = c.hex; text = c.hex }
            } label: { Image(systemName: "eyedropper") }
                .buttonStyle(.bordered).buttonBorderShape(.circle)
                .help("Pick \(label.lowercased()) from screen")
                .accessibilityLabel("Pick \(label.lowercased()) color from screen")
        }
        .padding(.leading, 12).padding(.trailing, 6).frame(minHeight: 40)
        .well()
    }
}
