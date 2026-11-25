import SwiftUI

struct UnitsTool: View {
    @AppStorage("units.base") private var base: Double = 16
    @AppStorage("units.px") private var px: Double = 24

    private let common: [Double] = [2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 80, 96]

    /// rem is derived from px; editing it writes back px. px is the single source of truth.
    private var rem: Binding<Double> {
        Binding(get: { px / base }, set: { px = $0 * base })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            Group {
                HStack(spacing: 8) {
                    field(NumberField(placeholder: "Pixels", value: $px, unit: "px", font: big),
                          copy: "\(Num.fmt(px))px")
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    field(NumberField(placeholder: "Rem", value: rem, unit: "rem", font: big),
                          copy: "\(Num.fmt(px / base))rem")
                }
            }

            HStack {
                Text("Root font size").font(.callout)
                Spacer()
                Stepper(value: $base, in: 8...32, step: 1) {
                    Text("\(Num.fmt(base))px").font(.system(size: 12, design: .monospaced))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
            .well()

            VStack(alignment: .leading, spacing: 8) {
                Text("Common sizes at \(Num.fmt(base))px root · click to use & copy")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(common, id: \.self) { v in
                        Button {
                            px = v
                            Clipboard.copy("\(Num.fmt(v / base))rem")
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(Num.fmt(v))px").font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text("\(Num.fmt(v / base))rem").font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .chip(v == px)
                        .help("Tailwind spacing: \(Num.fmt(v / 4))")
                        .accessibilityAddTraits(v == px ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var big: Font { .system(size: 22, weight: .semibold, design: .monospaced) }

    private func field(_ f: NumberField, copy: String) -> some View {
        HStack(spacing: 4) {
            f
            Button { Clipboard.copy(copy) } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Copy \(copy)").accessibilityLabel("Copy \(copy)")
        }
        .padding(.horizontal, 12).frame(height: 48)
        .well()
    }
}
