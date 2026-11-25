import SwiftUI
import AppKit

/// Everyday text transforms: JSON, Base64, URL encoding, naming cases.
struct TextTool: View {
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?
    @State private var lastOp: TextOp?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Input").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Paste") { input = NSPasteboard.general.string(forType: .string) ?? input; rerun() }
                    Button("Lorem") { input = TextOp.lorem; rerun() }
                    Button("Clear") { input = ""; output = ""; error = nil; lastOp = nil }
                }
                .buttonStyle(.borderless).font(.caption)
                editor($input, placeholder: "Paste JSON, text, a URL…")
                    .onChange(of: input) { _, _ in rerun() }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(TextOp.allCases) { op in
                    let on = op == lastOp
                    Button { run(op) } label: {
                        Text(op.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: op.isCase ? .monospaced : .default))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(on ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .chip(on)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Output").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(stats).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button { copyFull() } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless).font(.caption)
                    .disabled(output.isEmpty)
                    Button("Use as input") { input = output }
                        .buttonStyle(.borderless).font(.caption)
                        .disabled(output.isEmpty)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                ScrollView {
                    Text(output.isEmpty ? "Pick a transform above" : output)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(output.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .frame(height: 110)
                .well()
            }
        }
    }

    private var stats: String {
        let s = output.isEmpty ? input : output
        let words = s.split { $0.isWhitespace || $0.isNewline }.count
        let lines = s.isEmpty ? 0 : s.components(separatedBy: .newlines).count
        return "\(s.count) chars · \(words) words · \(lines) lines"
    }

    private func copyFull() {
        // HUD shows a short preview; the clipboard gets the full text.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        let oneLine = output.replacingOccurrences(of: "\n", with: " ")
        CopyHUD.shared.show(text: oneLine.count > 48 ? "\(oneLine.prefix(45))…" : oneLine, swatch: nil, symbol: "doc.on.doc")
    }

    private func run(_ op: TextOp) {
        lastOp = op
        rerun()
    }

    private func rerun() {
        guard let op = lastOp, !input.isEmpty else { output = ""; error = nil; return }
        do { output = try op.apply(input); error = nil }
        catch { output = ""; self.error = error.localizedDescription }
    }

    private func editor(_ text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .accessibilityLabel("Input text")
            if text.wrappedValue.isEmpty {
                Text(placeholder).font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 11).padding(.vertical, 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 96)
        .well()
    }
}

enum TextOp: String, CaseIterable, Identifiable {
    case formatJSON = "Format JSON", minifyJSON = "Minify JSON", sortJSON = "Sort keys"
    case b64Encode = "Base64 encode", b64Decode = "Base64 decode", urlEncode = "URL encode"
    case urlDecode = "URL decode", camel = "camelCase", pascal = "PascalCase"
    case kebab = "kebab-case", snake = "snake_case", constant = "CONST_CASE"

    var id: String { rawValue }
    var isCase: Bool { [.camel, .pascal, .kebab, .snake, .constant].contains(self) }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    func apply(_ s: String) throws -> String {
        switch self {
        case .formatJSON: return try json(s, [.prettyPrinted, .withoutEscapingSlashes])
        case .minifyJSON: return try json(s, [.withoutEscapingSlashes])
        case .sortJSON: return try json(s, [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        case .b64Encode: return Data(s.utf8).base64EncodedString()
        case .b64Decode:
            var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while t.count % 4 != 0 { t += "=" }
            guard let d = Data(base64Encoded: t) else { throw Failure("Not valid Base64.") }
            guard let out = String(data: d, encoding: .utf8) else { throw Failure("Decoded data isn't UTF‑8 text (\(d.count) bytes).") }
            return out
        case .urlEncode:
            var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        case .urlDecode:
            guard let out = s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            else { throw Failure("Invalid percent-encoding.") }
            return out
        case .camel:
            let w = Self.words(s).map { $0.lowercased() }
            return (w.first ?? "") + w.dropFirst().map(\.capitalized).joined()
        case .pascal: return Self.words(s).map { $0.lowercased().capitalized }.joined()
        case .kebab: return Self.words(s).map { $0.lowercased() }.joined(separator: "-")
        case .snake: return Self.words(s).map { $0.lowercased() }.joined(separator: "_")
        case .constant: return Self.words(s).map { $0.uppercased() }.joined(separator: "_")
        }
    }

    private func json(_ s: String, _ opts: JSONSerialization.WritingOptions) throws -> String {
        do {
            let obj = try JSONSerialization.jsonObject(with: Data(s.utf8), options: [.fragmentsAllowed])
            let data = try JSONSerialization.data(withJSONObject: obj, options: opts.union(.fragmentsAllowed))
            return String(decoding: data, as: UTF8.self)
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
            throw Failure("Invalid JSON\(detail.map { ": \($0)" } ?? ".")")
        }
    }

    /// Splits "helloWorld foo-bar_baz" → ["hello", "World", "foo", "bar", "baz"].
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = ""
        var prev: Character?
        for ch in s {
            if ch.isLetter || ch.isNumber {
                if let p = prev, p.isLowercase || p.isNumber, ch.isUppercase, !cur.isEmpty {
                    out.append(cur); cur = ""
                }
                cur.append(ch)
            } else if !cur.isEmpty {
                out.append(cur); cur = ""
            }
            prev = ch
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
}
