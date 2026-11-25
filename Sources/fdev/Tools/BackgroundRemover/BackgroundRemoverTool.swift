import SwiftUI
import UniformTypeIdentifiers

struct BackgroundRemoverTool: View {
    @ObservedObject private var m = BackgroundRemoverModel.shared
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            if m.batch.isEmpty { canvas } else { batchList }

            if let e = m.error {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let method = m.method, m.output != nil {
                methodNote(method)
            }

            actions

            VStack(alignment: .leading, spacing: 12) {
                field("Method") {
                    Picker("Method", selection: $m.mode) {
                        ForEach(BGMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                .help(m.mode.help)

                if m.mode != .subject {
                    field("Tolerance") {
                        HStack(spacing: 8) {
                            Slider(value: $m.tolerance, in: 0...100)
                                .accessibilityLabel("Tolerance")
                            Text("\(Int(m.tolerance))").monospacedDigit()
                                .frame(minWidth: 24, alignment: .trailing)
                        }
                    }
                    .help("Higher removes colors further from the background. Raise it for JPEG noise or soft shadows.")
                }

                field("Background") {
                    HStack(spacing: 8) {
                        Picker("Background", selection: $m.fill) {
                            ForEach(BGFill.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        if m.fill == .color {
                            ColorPicker("Fill color", selection: $m.fillColor, supportsOpacity: false)
                                .labelsHidden().fixedSize()
                        }
                    }
                }

                Toggle("Crop to subject", isOn: $m.crop)
            }
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .well()

            Text(m.mode.help + " Runs on‑device · nothing uploaded.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pieces

    /// Label above a full-width control — never squeezes the label in a narrow panel.
    private func field<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { m.openFile() } label: { Label("Open Images…", systemImage: "folder") }
                Button { m.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }
                    .keyboardShortcut("v")
                Spacer(minLength: 0)
                if !m.batch.isEmpty && !m.batchRunning {
                    Button { m.revealBatch() } label: { Label("Show in Finder", systemImage: "folder") }
                        .buttonStyle(.borderedProminent)
                }
            }
            if m.output != nil {
                HStack(spacing: 8) {
                    Button { m.showOriginal.toggle() } label: {
                        Label(m.showOriginal ? "Result" : "Original",
                              systemImage: m.showOriginal ? "wand.and.stars" : "photo")
                    }
                    .help("Compare with the original (⌘O)")
                    .keyboardShortcut("o")
                    Button { m.copyResult() } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .help("Copy PNG")
                        .keyboardShortcut("c")
                    Spacer(minLength: 0)
                    Button { m.save() } label: { Label("Save PNG…", systemImage: "square.and.arrow.down") }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s")
                }
            }
        }
        .controlSize(.large)
        .lineLimit(1)
    }

    private func methodNote(_ method: BackgroundRemover.Method) -> some View {
        HStack(spacing: 6) {
            switch method {
            case .subject:
                Image(systemName: "person.crop.rectangle").foregroundStyle(.secondary)
                Text("Subject lifted with Apple Vision")
            case .color(let c):
                RoundedRectangle(cornerRadius: 3).fill(Color(cgColor: c))
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5)))
                    .accessibilityHidden(true)
                Text("Removed solid background \(PickedColor(NSColor(cgColor: c) ?? .black)?.hex ?? "")")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private var canvas: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            if let out = m.outputImage, !m.showOriginal {
                if m.fill == .transparent { Checkerboard().opacity(0.6).clipShape(shape) }
                Image(nsImage: out)
                    .resizable().scaledToFit()
                    .padding(16)
                    .onDrag {
                        m.tempFileURL().flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider()
                    }
                    .help("Drag the result into Figma, Finder, your editor…")
                    .transition(.opacity)
                overlayBar(label: "Result · drag to export")
            } else if let input = m.input {
                Image(nsImage: input)
                    .resizable().scaledToFit()
                    .padding(16)
                    .opacity(m.isWorking ? 0.35 : 1)
                    .blur(radius: m.isWorking ? 2 : 0)
                if m.isWorking {
                    VStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Removing background…").font(.caption.weight(.medium))
                    }
                    .padding(14)
                    .well()
                }
                overlayBar(label: m.showOriginal ? "Original" : nil)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                        .symbolEffect(.bounce, value: targeted)
                    Text("Drop images here").font(.headline)
                    Text("One image to edit, or several to process them all.\nOr paste ⌘V · Open Images…")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260, maxHeight: .infinity)
        .background(shape.fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(Color.accentColor.opacity(targeted ? 0.9 : 0)))
        .animation(.easeOut(duration: 0.2), value: m.output != nil)
        .animation(.easeOut(duration: 0.15), value: m.showOriginal)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .onDrop(of: [.fileURL, .image], isTargeted: $targeted, perform: handleDrop)
    }

    private func overlayBar(label: String?) -> some View {
        VStack {
            HStack {
                if let label {
                    Text(label).font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button { m.reset() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                    .help("Clear").accessibilityLabel("Clear")
            }
            Spacer()
        }
        .padding(10)
    }

    private var batchList: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let done = m.batch.filter { if case .done = $0.state { true } else { false } }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(m.batchRunning ? "Processing \(done + 1) of \(m.batch.count)…" : "\(done) of \(m.batch.count) saved next to the originals")
                    .font(.callout.weight(.medium))
                Spacer()
                if !m.batchRunning {
                    Button { m.reset() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                        .help("Clear").accessibilityLabel("Clear")
                }
            }
            .padding(12)
            ProgressView(value: Double(m.batch.filter { if case .pending = $0.state { false } else if case .working = $0.state { false } else { true } }.count),
                         total: Double(max(1, m.batch.count)))
                .padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(m.batch) { item in
                        HStack(spacing: 8) {
                            Group {
                                switch item.state {
                                case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
                                case .working: ProgressView().controlSize(.small)
                                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                }
                            }
                            .frame(width: 18)
                            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            switch item.state {
                            case .done(let u):
                                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                                    .buttonStyle(.link).font(.caption)
                            case .failed(let e):
                                Text(e).font(.caption).foregroundStyle(.orange).lineLimit(1).help(e)
                            default: EmptyView()
                            }
                        }
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(targeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
        .onDrop(of: [.fileURL, .image], isTargeted: $targeted, perform: handleDrop)
    }

    // MARK: Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if !files.isEmpty {
            Task {
                var urls: [URL] = []
                for p in files {
                    if let u = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let url = URL(dataRepresentation: u, relativeTo: nil) { urls.append(url) }
                }
                await MainActor.run { m.load(urls: urls) }
            }
            return true
        }
        if let p = providers.first, p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data, let img = NSImage(data: data) {
                    Task { @MainActor in m.load(img, name: "dropped") }
                }
            }
            return true
        }
        return false
    }
}

/// Transparency checkerboard.
struct Checkerboard: View {
    var cell: CGFloat = 10
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
            for r in 0..<rows {
                for c in 0..<cols where (r + c).isMultiple(of: 2) {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)),
                             with: .color(.gray.opacity(0.35)))
                }
            }
        }
    }
}
