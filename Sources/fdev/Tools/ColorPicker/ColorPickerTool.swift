import SwiftUI

struct ColorPickerTool: View {
    @ObservedObject private var store = ColorStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            MenuRow(action: { store.pick() }) {
                IconCircle(symbol: "eyedropper", active: true)
                Text("Pick a color").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
                Text("⌥⌘C").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .keyboardShortcut("p")

            if let c = store.selected {
                Hero(color: c)
                FormatList(color: c)
            } else {
                EmptyState()
            }

            if !store.history.isEmpty { HistoryGrid() }

            HStack(spacing: 12) {
                Toggle("Auto‑copy", isOn: $store.autoCopy)
                    .toggleStyle(.switch).controlSize(.mini).font(.caption)
                Picker("Auto‑copy format", selection: $store.autoCopyFormat) {
                    ForEach(ColorFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().controlSize(.small).fixedSize()
                .disabled(!store.autoCopy)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: store.selected)
    }
}

// MARK: - Hero swatch

private struct Hero: View {
    let color: PickedColor

    var body: some View {
        // Choose whichever text color actually contrasts more with the swatch.
        let darkText = color.contrast(with: 0) >= color.contrast(with: 1)
        let fg: Color = darkText ? .black : .white
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        Button { ColorStore.shared.copy(color, as: .hex) } label: {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(color.cssHex).font(.system(size: 26, weight: .bold, design: .monospaced))
                    Text("rgb \(color.r8) \(color.g8) \(color.b8)")
                        .font(.system(size: 11, design: .monospaced))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    ContrastLine(label: "on white", ratio: color.contrast(with: 1))
                    ContrastLine(label: "on black", ratio: color.contrast(with: 0))
                }
            }
            .foregroundStyle(fg)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .bottomLeading)
            .background(shape.fill(color.color))
            // Boundary matters: a swatch close to the window color would otherwise vanish.
            .overlay(shape.strokeBorder(.primary.opacity(0.2), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help("Copy HEX")
        .accessibilityLabel("\(color.hex). Copy HEX")
    }
}

private struct ContrastLine: View {
    let label: String
    let ratio: Double
    var grade: String { ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? "AA Large" : "Fail" }

    var body: some View {
        Text("\(String(format: "%.1f", ratio)) \(grade) \(label)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}

// MARK: - Formats

private struct FormatList: View {
    let color: PickedColor
    var body: some View {
        VStack(spacing: 0) {
            ForEach(ColorFormat.allCases) { f in
                FormatRow(color: color, format: f)
            }
        }
    }
}

private struct FormatRow: View {
    let color: PickedColor
    let format: ColorFormat
    @State private var hover = false

    var body: some View {
        Button { ColorStore.shared.copy(color, as: format) } label: {
            HStack(spacing: 12) {
                Text(format.rawValue)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Text(color.string(format))
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .opacity(hover ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8).frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Copy \(format.rawValue): \(color.string(format))")
    }
}

// MARK: - History

private struct HistoryGrid: View {
    @ObservedObject private var store = ColorStore.shared
    // Adaptive columns: fills whatever width is available instead of forcing it wider.
    private let cols = [GridItem(.adaptive(minimum: 28, maximum: 28), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("History").font(.caption.weight(.semibold))
                Text("\(store.history.count)").font(.caption2)
                Spacer()
                Button("Copy as CSS") { store.copyPalette() }
                    .buttonStyle(.borderless).font(.caption)
                Button { store.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).font(.caption)
                    .help("Clear history").accessibilityLabel("Clear history")
            }
            .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(store.history) { c in
                        Swatch(color: c, selected: c.id == store.selected?.id)
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 84)
        }
    }
}

private struct Swatch: View {
    let color: PickedColor
    let selected: Bool
    @State private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button { ColorStore.shared.selected = color } label: {
            shape.fill(color.color)
                .frame(width: 28, height: 28)
                .overlay(shape.strokeBorder(.primary.opacity(0.2), lineWidth: 1))
                // Selection: an outer ring + check mark, so it's not color-only and persists.
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color.contrast(with: 0) >= color.contrast(with: 1) ? .black : .white)
                    }
                }
                .padding(2)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                .scaleEffect(hover ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(color.hex)
        .accessibilityLabel(color.hex)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            ForEach(ColorFormat.allCases) { f in
                Button("Copy \(f.rawValue)") { ColorStore.shared.copy(color, as: f) }
            }
            Divider()
            Button("Remove", role: .destructive) { ColorStore.shared.remove(color) }
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eyedropper.halffull")
                .font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No colors yet").font(.headline)
            Text("Press **⌥⌘C** anywhere, then click any pixel — any app, any window, any display.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24).padding(.horizontal, 20)
        .well()
    }
}
