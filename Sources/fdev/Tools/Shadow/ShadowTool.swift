import SwiftUI
import AppKit

struct ShadowLayer: Codable, Identifiable, Equatable {
    var id = UUID()
    var x: Double = 0
    var y: Double = 4
    var blur: Double = 6
    var spread: Double = -1
    var color: String = "#000000"
    var opacity: Double = 0.1

    private func px(_ v: Double) -> String { v == 0 ? "0" : "\(Num.fmt(v))px" }

    var rgb: (Int, Int, Int) {
        let c = PickedColor(hex: color)
        return (c?.r8 ?? 0, c?.g8 ?? 0, c?.b8 ?? 0)
    }

    var css: String {
        let (r, g, b) = rgb
        return "\(px(x)) \(px(y)) \(px(blur)) \(px(spread)) rgb(\(r) \(g) \(b) / \(Num.fmt(opacity, decimals: 2)))"
    }

    var swiftUI: String {
        let (r, g, b) = rgb
        let color = (r, g, b) == (0, 0, 0) ? ".black" : "Color(red: \(Num.fmt(Double(r) / 255, decimals: 3)), green: \(Num.fmt(Double(g) / 255, decimals: 3)), blue: \(Num.fmt(Double(b) / 255, decimals: 3)))"
        return ".shadow(color: \(color).opacity(\(Num.fmt(opacity, decimals: 2))), radius: \(Num.fmt(blur / 2)), x: \(Num.fmt(x)), y: \(Num.fmt(y)))"
    }
}

@MainActor
final class ShadowModel: ObservableObject {
    static let shared = ShadowModel()

    @Published var layers: [ShadowLayer] { didSet { save() } }
    @Published var selected: Int = 0

    static let presets: [(String, [ShadowLayer])] = [
        ("sm", [ShadowLayer(y: 1, blur: 2, spread: 0, opacity: 0.05)]),
        ("base", [ShadowLayer(y: 1, blur: 3, spread: 0, opacity: 0.1), ShadowLayer(y: 1, blur: 2, spread: -1, opacity: 0.1)]),
        ("md", [ShadowLayer(y: 4, blur: 6, spread: -1, opacity: 0.1), ShadowLayer(y: 2, blur: 4, spread: -2, opacity: 0.1)]),
        ("lg", [ShadowLayer(y: 10, blur: 15, spread: -3, opacity: 0.1), ShadowLayer(y: 4, blur: 6, spread: -4, opacity: 0.1)]),
        ("xl", [ShadowLayer(y: 20, blur: 25, spread: -5, opacity: 0.1), ShadowLayer(y: 8, blur: 10, spread: -6, opacity: 0.1)]),
        ("2xl", [ShadowLayer(y: 25, blur: 50, spread: -12, opacity: 0.25)]),
    ]

    init() {
        if let d = UserDefaults.standard.data(forKey: "shadow.layers"),
           let l = try? JSONDecoder().decode([ShadowLayer].self, from: d), !l.isEmpty {
            layers = l
        } else {
            layers = Self.presets[2].1
        }
    }

    func reload() {
        if let d = UserDefaults.standard.data(forKey: "shadow.layers"),
           let l = try? JSONDecoder().decode([ShadowLayer].self, from: d), !l.isEmpty, l != layers {
            layers = l
            selected = min(selected, l.count - 1)
        }
    }

    var css: String { "box-shadow: \(layers.map(\.css).joined(separator: ", "));" }
    var tailwind: String {
        "shadow-[\(layers.map(\.css).joined(separator: ",").replacingOccurrences(of: " ", with: "_"))]"
    }
    var swiftUI: String { layers.map(\.swiftUI).joined(separator: "\n") }

    func apply(_ preset: [ShadowLayer]) {
        layers = preset.map { var l = $0; l.id = UUID(); return l }
        selected = 0
    }

    func addLayer() {
        guard layers.count < 5 else { return }
        layers.append(ShadowLayer(y: 8, blur: 16, spread: 0, opacity: 0.12))
        selected = layers.count - 1
    }

    func removeSelected() {
        guard layers.count > 1 else { return }
        layers.remove(at: selected)
        selected = min(selected, layers.count - 1)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(layers) { UserDefaults.standard.set(d, forKey: "shadow.layers") }
    }
}

struct ShadowTool: View {
    @ObservedObject private var m = ShadowModel.shared
    @State private var dark = false

    private var layer: Binding<ShadowLayer> {
        Binding(get: { m.layers[min(m.selected, m.layers.count - 1)] },
                set: { m.layers[min(m.selected, m.layers.count - 1)] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            ZStack(alignment: .topTrailing) {
                ShadowPreview(layers: m.layers, dark: dark)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 1))
                    .accessibilityLabel("Shadow preview")
                Button { dark.toggle() } label: { Image(systemName: dark ? "sun.max" : "moon") }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                    .padding(8)
                    .help(dark ? "Light preview" : "Dark preview")
                    .accessibilityLabel(dark ? "Light preview" : "Dark preview")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Tailwind presets").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Group {
                    HStack(spacing: 6) {
                        ForEach(ShadowModel.presets, id: \.0) { p in
                            Button { m.apply(p.1) } label: {
                                Text(p.0).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .frame(maxWidth: .infinity, minHeight: 26)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .chip(false)
                            .accessibilityLabel("Preset shadow-\(p.0)")
                        }
                    }
                }
            }

            // Layer picker
            HStack(spacing: 6) {
                Text("Layers").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(m.layers.indices, id: \.self) { i in
                    let on = i == m.selected
                    Button("\(i + 1)") { m.selected = i }
                        .font(.system(size: 12, weight: on ? .bold : .regular, design: .monospaced))
                        .frame(width: 28, height: 24)
                        .foregroundStyle(on ? Color.accentColor : Color.primary)
                        .buttonStyle(.plain)
                        .chip(on)
                        .accessibilityLabel("Layer \(i + 1)")
                        .accessibilityAddTraits(on ? .isSelected : [])
                }
                Button { m.addLayer() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless).disabled(m.layers.count >= 5)
                    .help("Add layer").accessibilityLabel("Add layer")
                Button { m.removeSelected() } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless).disabled(m.layers.count <= 1)
                    .help("Remove layer").accessibilityLabel("Remove layer")
                Spacer()
            }

            VStack(spacing: 4) {
                slider("X", layer.x, -50...50)
                slider("Y", layer.y, -50...50)
                slider("Blur", layer.blur, 0...100)
                slider("Spread", layer.spread, -50...50)
                slider("Opacity", layer.opacity, 0...1, step: 0.01, unit: "")
                HStack(spacing: 12) {
                    Text("Color").font(.callout).frame(width: 58, alignment: .leading)
                    RoundedRectangle(cornerRadius: 4).fill(PickedColor(hex: layer.wrappedValue.color)?.color ?? .black)
                        .frame(width: 18, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.2)))
                    TextField("#000000", text: layer.color)
                        .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                        .accessibilityLabel("Shadow color HEX")
                    Button {
                        ColorStore.shared.sample { c in layer.wrappedValue.color = c.hex }
                    } label: { Image(systemName: "eyedropper") }
                        .buttonStyle(.borderless).help("Pick from screen").accessibilityLabel("Pick shadow color from screen")
                }
                .frame(minHeight: 28)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .well()

            VStack(alignment: .leading, spacing: 8) {
                Text(m.css)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    HStack(spacing: 8) {
                        Button { Clipboard.copy(m.css) } label: { Label("CSS", systemImage: "doc.on.doc") }
                            .buttonStyle(.borderedProminent)
                        Button("Tailwind") { Clipboard.copy(m.tailwind) }.buttonStyle(.bordered)
                        Button("SwiftUI") { Clipboard.copy(m.swiftUI) }.buttonStyle(.bordered)
                            .help("SwiftUI has no spread — it's ignored")
                    }
                    .controlSize(.small)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .well()
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        step: Double = 1, unit: String = "px") -> some View {
        HStack(spacing: 12) {
            Text(title).font(.callout).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range, step: step).controlSize(.small)
                .accessibilityLabel(title)
            Text("\(Num.fmt(value.wrappedValue, decimals: 2))\(unit)")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(minHeight: 28)
    }
}

/// Renders CSS-like box-shadows with Core Animation (supports spread via shadowPath).
struct ShadowPreview: NSViewRepresentable {
    let layers: [ShadowLayer]
    let dark: Bool

    func makeNSView(context: Context) -> ShadowCanvas { ShadowCanvas() }
    func updateNSView(_ v: ShadowCanvas, context: Context) {
        v.model = layers
        v.dark = dark
        v.needsLayout = true
    }
}

final class ShadowCanvas: NSView {
    var model: [ShadowLayer] = []
    var dark = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        root.backgroundColor = dark ? NSColor(white: 0.1, alpha: 1).cgColor : NSColor(white: 0.95, alpha: 1).cgColor
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let card = CGRect(x: bounds.midX - 80, y: bounds.midY - 45, width: 160, height: 90)
        // CSS paints the first shadow on top, so add in reverse.
        for l in model.reversed() {
            let s = CALayer()
            s.frame = bounds
            let r = card.insetBy(dx: -l.spread, dy: -l.spread)
            let radius = max(0, 14 + l.spread)
            if r.width > 0, r.height > 0 {
                s.shadowPath = CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2),
                                      cornerHeight: min(radius, r.height / 2), transform: nil)
            }
            let (cr, cg, cb) = l.rgb
            s.shadowColor = CGColor(srgbRed: CGFloat(cr) / 255, green: CGFloat(cg) / 255, blue: CGFloat(cb) / 255, alpha: 1)
            s.shadowOpacity = Float(l.opacity)
            s.shadowRadius = l.blur / 2                       // CSS blur ≈ 2σ
            s.shadowOffset = CGSize(width: l.x, height: -l.y) // AppKit y points up
            root.addSublayer(s)
        }
        let c = CALayer()
        c.frame = card
        c.cornerRadius = 14
        c.backgroundColor = dark ? NSColor(white: 0.18, alpha: 1).cgColor : NSColor.white.cgColor
        root.addSublayer(c)
        CATransaction.commit()
    }
}
