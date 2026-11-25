import SwiftUI

/// Generates a fluid `clamp()` that scales linearly between two viewport widths.
struct FluidTypeTool: View {
    @AppStorage("fluid.minSize") private var minSize: Double = 16
    @AppStorage("fluid.maxSize") private var maxSize: Double = 24
    @AppStorage("fluid.minVW") private var minVW: Double = 375
    @AppStorage("fluid.maxVW") private var maxVW: Double = 1440
    @AppStorage("units.base") private var base: Double = 16

    private var valid: Bool { maxVW > minVW && minSize > 0 && maxSize > 0 }
    private var slope: Double { (maxSize - minSize) / (maxVW - minVW) }
    private var intercept: Double { minSize - slope * minVW }

    private func rem(_ px: Double) -> String { "\(Num.fmt(px / base))rem" }

    var clamp: String {
        guard valid else { return "" }
        let lo = min(minSize, maxSize), hi = max(minSize, maxSize)
        let sign = intercept < 0 ? "-" : "+"
        // Written as "vw + rem" so it still respects the user's browser font size.
        return "clamp(\(rem(lo)), \(Num.fmt(slope * 100))vw \(sign) \(rem(abs(intercept))), \(rem(hi)))"
    }

    func size(at vw: Double) -> Double {
        let v = intercept + slope * vw
        return min(max(v, min(minSize, maxSize)), max(minSize, maxSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    input("Min size", $minSize)
                    input("Max size", $maxSize)
                }
                GridRow {
                    input("Min viewport", $minVW)
                    input("Max viewport", $maxVW)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if valid {
                    Text(clamp)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        HStack(spacing: 8) {
                            Button { Clipboard.copy(clamp) } label: { Label("Copy clamp()", systemImage: "doc.on.doc") }
                                .buttonStyle(.borderedProminent)
                            Button { Clipboard.copy("font-size: \(clamp);") } label: { Text("Copy as font-size") }
                                .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Label("Max viewport must be larger than min viewport.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .well()

            if valid {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resolved size").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach([320.0, 375, 768, 1024, 1280, 1440, 1920], id: \.self) { vw in
                        HStack(spacing: 12) {
                            Text("\(Int(vw))").font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                            Text("Aa")
                                .font(.system(size: min(size(at: vw), 40), weight: .semibold))
                                .lineLimit(1)
                                .frame(width: 56, alignment: .leading)
                            Text("\(Num.fmt(size(at: vw), decimals: 2))px")
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Text("Uses the \(Num.fmt(base))px root from px ↔ rem.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func input(_ title: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            NumberField(placeholder: title, value: value, unit: "px")
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .well()
    }
}
