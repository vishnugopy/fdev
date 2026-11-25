import SwiftUI
import UniformTypeIdentifiers

struct ImageConvertTool: View {
    @ObservedObject private var m = ImageConvertModel.shared
    @State private var targeted = false

    private let sizes = [0, 3840, 2560, 1920, 1280, 800, 400]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            canvas
            if let e = m.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if m.source != nil { stats }

            VStack(spacing: 0) {
                row("Format") {
                    Picker("Format", selection: $m.format) {
                        ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                Divider().opacity(0.6)
                row("Quality") {
                    HStack(spacing: 8) {
                        Slider(value: $m.quality, in: 0.1...1, step: 0.05).frame(width: 140)
                            .accessibilityLabel("Quality")
                        Text("\(Int((m.quality * 100).rounded()))%")
                            .font(.system(size: 12, design: .monospaced)).frame(width: 38, alignment: .trailing)
                    }
                }
                .disabled(!m.format.lossy)
                Divider().opacity(0.6)
                row("Max size") {
                    Picker("Max size", selection: $m.maxDimension) {
                        ForEach(sizes, id: \.self) { Text($0 == 0 ? "Original" : "\($0)px").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .well()

            Group {
                HStack(spacing: 8) {
                    Button { m.openFile() } label: { Image(systemName: "folder") }
                        .buttonStyle(.bordered).help("Open").accessibilityLabel("Open image")
                    Button { m.paste() } label: { Image(systemName: "doc.on.clipboard") }
                        .buttonStyle(.bordered).help("Paste").accessibilityLabel("Paste image")
                        .keyboardShortcut("v")
                    Spacer(minLength: 0)
                    if m.output != nil {
                        Button("Data URI") { m.copyDataURI() }.buttonStyle(.bordered)
                        Button { m.copyImage() } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.bordered).help("Copy image").accessibilityLabel("Copy image")
                        Button { m.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.borderedProminent).keyboardShortcut("s")
                    }
                }
                .controlSize(.large)
            }
        }
    }

    private var canvas: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            if let img = m.previewImage {
                Checkerboard().opacity(0.5).clipShape(shape)
                Image(nsImage: img).resizable().scaledToFit().padding(12)
                    .opacity(m.isWorking ? 0.5 : 1)
                    .onDrag { m.tempFileURL().flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
                    .help("Drag the converted file anywhere")
                if m.isWorking { ProgressView().controlSize(.small).padding(12).well() }
                VStack {
                    HStack {
                        Spacer()
                        Button { m.reset() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                            .help("Clear").accessibilityLabel("Clear image")
                    }
                    Spacer()
                }
                .padding(10)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Drop an image").font(.headline)
                    Text("or paste ⌘V · open a file\nConverts to AVIF, JPEG, PNG or HEIC — metadata stripped")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .background(shape.fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(Color.accentColor.opacity(targeted ? 0.9 : 0)))
        .onDrop(of: [.fileURL, .image], isTargeted: $targeted) { providers in
            guard let p = providers.first else { return false }
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = p.loadObject(ofClass: URL.self) { u, _ in if let u { Task { @MainActor in m.load(url: u) } } }
                return true
            }
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { d, _ in
                if let d { Task { @MainActor in m.load(d, name: "dropped") } }
            }
            return true
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Original").font(.caption2).foregroundStyle(.secondary)
                Text(m.source.map { ImageConvertModel.bytes($0.count) } ?? "–").font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(dims(m.sourceSize)).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.format.rawValue).font(.caption2).foregroundStyle(.secondary)
                Text(m.output.map { ImageConvertModel.bytes($0.count) } ?? "…").font(.system(size: 13, weight: .semibold, design: .monospaced))
                Text(dims(m.outputSize)).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            if let s = m.savingsText {
                Text(s).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("Size change \(s)")
            }
        }
    }

    private func dims(_ s: CGSize?) -> String {
        s.map { "\(Int($0.width))×\(Int($0.height))" } ?? " "
    }

    private func row<T: View>(_ label: String, @ViewBuilder _ trailing: () -> T) -> some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            trailing()
        }
        .frame(minHeight: 36)
        .controlSize(.small)
    }
}
