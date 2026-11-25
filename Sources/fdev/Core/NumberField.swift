import SwiftUI

/// CSS-style number helpers: accept "1,5" or "1.5", always write "1.5".
enum Num {
    static func parse(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    static func fmt(_ v: Double, decimals: Int = 4) -> String {
        guard v.isFinite else { return "0" }
        var s = String(format: "%.\(decimals)f", v)          // POSIX: always "."
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }
}

/// A numeric field that never rewrites itself while you type.
/// It only reformats when it loses focus or when the value changes from elsewhere.
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double
    var unit: String = ""
    var font: Font = .system(size: 13, weight: .semibold, design: .monospaced)

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onSubmit { text = Num.fmt(value) }
                .accessibilityLabel(placeholder)
            if !unit.isEmpty {
                Text(unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .onAppear { text = Num.fmt(value) }
        .onChange(of: text) { _, t in
            if focused, let v = Num.parse(t), v != value { value = v }
        }
        .onChange(of: value) { _, v in
            if !focused { text = Num.fmt(v) }
        }
        .onChange(of: focused) { _, f in
            if !f { text = Num.fmt(value) }
        }
    }
}
