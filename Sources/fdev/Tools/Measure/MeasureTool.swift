import SwiftUI

struct MeasureTool: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            MenuRow(action: { ScreenRuler.shared.start() }) {
                IconCircle(symbol: "ruler", active: true)
                Text("Start measuring").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 8)
                Text("⌥⌘M").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .keyboardShortcut("m")

            VStack(alignment: .leading, spacing: 12) {
                tip("cursorarrow.motionlines", "Hover to see x, y from the screen's top-left")
                tip("rectangle.dashed", "Drag a box to get width × height in CSS px")
                tip("return", "Return, ⌘C or double-click copies “W×H”")
                tip("escape", "Esc closes the ruler")
                tip("keyboard", "Start from anywhere with ⌥⌘M")
            }
            .padding(.horizontal, Metrics.inset)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Sizes are in points, which equal CSS px at 100% browser zoom. The @2x line shows physical pixels on Retina displays.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .blockInset()
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.callout)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
        }
    }
}
