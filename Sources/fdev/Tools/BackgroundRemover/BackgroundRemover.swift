import AppKit
import SwiftUI
import Vision
import CoreImage
import UniformTypeIdentifiers

enum BGMode: String, CaseIterable, Identifiable {
    case auto = "Auto", subject = "Subject", color = "Solid color"
    var id: String { rawValue }
    var help: String {
        switch self {
        case .auto: "Logos and graphics on a plain background use color removal; photos use Apple Vision."
        case .subject: "Apple Vision lifts people, animals and objects — best for photos."
        case .color: "Removes the background color found around the edges, including inside letters and shapes — best for logos and icons."
        }
    }
}

/// On-device background removal: Apple Vision subject lifting for photos, color keying for graphics.
enum BackgroundRemover {
    enum Failure: LocalizedError {
        case noSubject, render, noSolidBackground
        var errorDescription: String? {
            switch self {
            case .noSubject: "Apple Vision found no subject. Try Solid color mode."
            case .render: "Couldn't render the result."
            case .noSolidBackground: "Nothing matched the background color. Raise the tolerance or try Subject mode."
            }
        }
    }

    enum Method { case subject, color(CGColor) }

    struct Result { let image: CGImage; let method: Method }

    static func remove(_ cg: CGImage, mode: BGMode, tolerance: Double, crop: Bool) throws -> Result {
        switch mode {
        case .subject:
            return Result(image: try lift(cg, crop: crop), method: .subject)
        case .color:
            return try colorKey(cg, tolerance: tolerance, crop: crop)
        case .auto:
            // A plain, even border means a graphic (logo, icon, screenshot) — color keying is exact there.
            if let px = Pixels(cg), px.borderUniformity(tolerance: tolerance) > 0.85 {
                return try colorKey(cg, tolerance: tolerance, crop: crop, pixels: px)
            }
            do { return Result(image: try lift(cg, crop: crop), method: .subject) }
            catch Failure.noSubject { return try colorKey(cg, tolerance: tolerance, crop: crop) }
        }
    }

    static func lift(_ cg: CGImage, crop: Bool) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        try handler.perform([request])
        guard let obs = request.results?.first, !obs.allInstances.isEmpty else { throw Failure.noSubject }
        let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler,
                                                 croppedToInstancesExtent: crop)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let out = CIContext().createCGImage(ci, from: ci.extent) else { throw Failure.render }
        return out
    }

    /// Removes every pixel close to the border's dominant color, with soft anti-aliased edges and
    /// color decontamination (no dark/light fringe around the artwork).
    static func colorKey(_ cg: CGImage, tolerance: Double, crop: Bool, pixels: Pixels? = nil) throws -> Result {
        guard var px = pixels ?? Pixels(cg) else { throw Failure.render }
        let bg = px.borderColor()
        let t = tolerance * 2.2            // slider 0…100 → RGB distance 0…220
        let feather = 48.0
        var removed = 0
        let bgR = Double(bg.r), bgG = Double(bg.g), bgB = Double(bg.b)
        px.data.withUnsafeMutableBufferPointer { d in
            var i = 0
            while i < d.count {
                let a0 = Double(d[i + 3]) / 255
                if a0 > 0 {
                    // un-premultiply
                    let r = Double(d[i]) / a0, g = Double(d[i + 1]) / a0, b = Double(d[i + 2]) / a0
                    let dist = ((r - bgR) * (r - bgR) + (g - bgG) * (g - bgG) + (b - bgB) * (b - bgB)).squareRoot()
                    var a = (dist - t) / feather
                    a = a < 0 ? 0 : (a > 1 ? 1 : a)
                    a = a * a * (3 - 2 * a)                      // smoothstep
                    if a < 1 {
                        if a < 0.5 { removed += 1 }
                        // premultiplied foreground = observed − background × (1 − α)
                        let k = 1 - a
                        let fa = a * a0
                        func ch(_ c: Double, _ bgc: Double) -> UInt8 {
                            let v = (c - bgc * k) * a0
                            return UInt8(max(0, min(fa * 255, v)).rounded())
                        }
                        d[i] = ch(r, bgR); d[i + 1] = ch(g, bgG); d[i + 2] = ch(b, bgB)
                        d[i + 3] = UInt8((fa * 255).rounded())
                    }
                }
                i += 4
            }
        }
        guard removed > px.width * px.height / 50 else { throw Failure.noSolidBackground }
        guard var out = px.makeImage() else { throw Failure.render }
        if crop, let box = px.opaqueBounds(), let c = out.cropping(to: box) { out = c }
        let color = CGColor(srgbRed: CGFloat(bg.r) / 255, green: CGFloat(bg.g) / 255, blue: CGFloat(bg.b) / 255, alpha: 1)
        return Result(image: out, method: .color(color))
    }
}

/// Plain RGBA8 (premultiplied, sRGB) pixel buffer.
struct Pixels {
    let width: Int, height: Int
    var data: [UInt8]

    init?(_ cg: CGImage) {
        width = cg.width; height = cg.height
        data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !ok { return nil }
    }

    func makeImage() -> CGImage? {
        var copy = data
        return copy.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    private func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    private var borderSamples: [(r: Int, g: Int, b: Int)] {
        var out: [(Int, Int, Int)] = []
        let stepX = max(1, width / 200), stepY = max(1, height / 200)
        for x in stride(from: 0, to: width, by: stepX) { out.append(rgb(x, 0)); out.append(rgb(x, height - 1)) }
        for y in stride(from: 0, to: height, by: stepY) { out.append(rgb(0, y)); out.append(rgb(width - 1, y)) }
        return out.map { (r: $0.0, g: $0.1, b: $0.2) }
    }

    /// Most common border color (bucketed, then averaged within the winning bucket).
    func borderColor() -> (r: Int, g: Int, b: Int) {
        let s = borderSamples
        var buckets: [Int: [(r: Int, g: Int, b: Int)]] = [:]
        for p in s { buckets[(p.r >> 4) << 8 | (p.g >> 4) << 4 | (p.b >> 4), default: []].append(p) }
        let best = buckets.values.max(by: { $0.count < $1.count }) ?? [(0, 0, 0)].map { (r: $0.0, g: $0.1, b: $0.2) }
        let n = best.count
        return (best.map(\.r).reduce(0, +) / n, best.map(\.g).reduce(0, +) / n, best.map(\.b).reduce(0, +) / n)
    }

    /// Share of border pixels close to the dominant border color.
    func borderUniformity(tolerance: Double) -> Double {
        let bg = borderColor(), s = borderSamples
        let t = max(30, tolerance * 2.2)
        let close = s.filter {
            let dr = Double($0.r - bg.r), dg = Double($0.g - bg.g), db = Double($0.b - bg.b)
            return (dr * dr + dg * dg + db * db).squareRoot() <= t
        }.count
        return s.isEmpty ? 0 : Double(close) / Double(s.count)
    }

    /// Bounding box of visible pixels, in CGImage (top-left origin) coordinates.
    func opaqueBounds() -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 10 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let pad = 2
        return CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                      width: min(width, maxX + pad + 1) - max(0, minX - pad),
                      height: min(height, maxY + pad + 1) - max(0, minY - pad))
    }
}

enum BGFill: String, CaseIterable, Identifiable {
    case transparent = "None", white = "White", black = "Black", color = "Color"
    var id: String { rawValue }
}

/// One file in a multi-image drop.
struct BatchItem: Identifiable {
    enum State { case pending, working, done(URL), failed(String) }
    let id = UUID()
    let url: URL
    var state: State = .pending
}

@MainActor
final class BackgroundRemoverModel: ObservableObject {
    static let shared = BackgroundRemoverModel()

    @Published var input: NSImage?
    /// The raw cut-out (transparent). `output` is this composited onto the chosen background.
    @Published private(set) var lifted: CGImage?
    @Published private(set) var output: CGImage?
    @Published var isWorking = false
    @Published var error: String?
    @Published var showOriginal = false
    @Published var crop: Bool = UserDefaults.standard.bool(forKey: "bg.crop") {
        didSet { UserDefaults.standard.set(crop, forKey: "bg.crop"); process() }
    }
    @Published var fill: BGFill = BGFill(rawValue: UserDefaults.standard.string(forKey: "bg.fill") ?? "") ?? .transparent {
        didSet { UserDefaults.standard.set(fill.rawValue, forKey: "bg.fill"); recomposite() }
    }
    @Published var fillColor: Color = PickedColor(hex: UserDefaults.standard.string(forKey: "bg.fillColor") ?? "")?.color
        ?? Color(red: 0.31, green: 0.55, blue: 1) {
        didSet {
            if let c = PickedColor(NSColor(fillColor)) { UserDefaults.standard.set(c.hex, forKey: "bg.fillColor") }
            recomposite()
        }
    }

    @Published var mode: BGMode = BGMode(rawValue: UserDefaults.standard.string(forKey: "bg.mode") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "bg.mode"); process() }
    }
    /// 0…100 — how far a color may be from the background and still be removed (Solid color mode).
    @Published var tolerance: Double = (UserDefaults.standard.object(forKey: "bg.tolerance") as? Double) ?? 25 {
        didSet { UserDefaults.standard.set(tolerance, forKey: "bg.tolerance"); scheduleProcess() }
    }
    @Published private(set) var method: BackgroundRemover.Method?

    // Batch
    @Published var batch: [BatchItem] = []
    @Published var batchRunning = false

    var sourceName = "image"

    var outputImage: NSImage? {
        output.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    var pngData: Data? { output.flatMap(Self.png) }

    nonisolated static func png(_ cg: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private var fillCGColor: CGColor? {
        switch fill {
        case .transparent: nil
        case .white: .white
        case .black: .black
        case .color: NSColor(fillColor).usingColorSpace(.sRGB)?.cgColor
        }
    }

    /// Puts the cut-out on a solid background (or leaves it transparent).
    nonisolated static func composite(_ cg: CGImage, on color: CGColor?) -> CGImage? {
        guard let color else { return cg }
        guard let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        let r = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        ctx.setFillColor(color); ctx.fill(r); ctx.draw(cg, in: r)
        return ctx.makeImage()
    }

    private func recomposite() {
        output = lifted.flatMap { Self.composite($0, on: fillCGColor) }
    }

    // MARK: Single image

    func load(_ image: NSImage, name: String = "image") {
        batch = []
        lifted = nil; output = nil; method = nil
        input = image
        sourceName = name
        showOriginal = false
        process()
    }

    func load(url: URL) {
        guard let img = NSImage(contentsOf: url) else { error = "That file isn't an image."; return }
        load(img, name: url.deletingPathExtension().lastPathComponent)
    }

    /// One URL → single mode; several → batch.
    func load(urls: [URL]) {
        let images = urls.filter { NSImage(contentsOf: $0) != nil }
        if images.count > 1 { runBatch(images) }
        else if let u = images.first { load(url: u) }
        else { error = "Those files aren't images." }
    }

    private var debounce: Task<Void, Never>?
    private var generation = 0

    /// Slider drags fire constantly — wait for a short pause before reprocessing.
    private func scheduleProcess() {
        debounce?.cancel()
        debounce = Task { try? await Task.sleep(for: .milliseconds(180)); if !Task.isCancelled { process() } }
    }

    func process() {
        guard let input, let cg = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        generation += 1
        let gen = generation
        isWorking = true
        error = nil
        let crop = self.crop, mode = self.mode, tol = self.tolerance
        Task.detached(priority: .userInitiated) {
            let result = Swift.Result { try BackgroundRemover.remove(cg, mode: mode, tolerance: tol, crop: crop) }
            await MainActor.run {
                guard gen == self.generation else { return }      // a newer run superseded this one
                self.isWorking = false
                switch result {
                case .success(let r): self.lifted = r.image; self.method = r.method; self.recomposite()
                case .failure(let e): self.lifted = nil; self.output = nil; self.method = nil
                    self.error = e.localizedDescription
                }
            }
        }
    }

    // MARK: Batch

    func runBatch(_ urls: [URL]) {
        reset()
        batch = urls.map { BatchItem(url: $0) }
        batchRunning = true
        let crop = self.crop, color = fillCGColor, mode = self.mode, tol = self.tolerance
        Task {
            for i in batch.indices {
                batch[i].state = .working
                let url = batch[i].url
                let result: Swift.Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                    Swift.Result {
                        guard let img = NSImage(contentsOf: url),
                              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
                        else { throw BackgroundRemover.Failure.render }
                        let lifted = try BackgroundRemover.remove(cg, mode: mode, tolerance: tol, crop: crop).image
                        guard let out = Self.composite(lifted, on: color), let data = Self.png(out)
                        else { throw BackgroundRemover.Failure.render }
                        let dest = Self.uniqueOutputURL(for: url)
                        try data.write(to: dest)
                        return dest
                    }
                }.value
                switch result {
                case .success(let dest): batch[i].state = .done(dest)
                case .failure(let e): batch[i].state = .failed(e.localizedDescription)
                }
            }
            batchRunning = false
            let done = batch.filter { if case .done = $0.state { true } else { false } }.count
            CopyHUD.shared.show(text: "\(done) of \(batch.count) saved", swatch: nil, symbol: "checkmark")
        }
    }

    /// photo.jpg → photo-nobg.png next to it (photo-nobg-2.png if that exists).
    nonisolated static func uniqueOutputURL(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + "-nobg"
        var candidate = dir.appendingPathComponent(base + ".png")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-\(n).png"); n += 1
        }
        return candidate
    }

    func revealBatch() {
        let urls = batch.compactMap { if case .done(let u) = $0.state { u } else { nil } }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    // MARK: Input & output

    func paste() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            load(urls: urls)
        } else if let img = NSImage(pasteboard: pb) {
            load(img, name: "pasted")
        } else {
            error = "No image on the clipboard."
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose one image, or several to process them all"
        NSApp.activate()
        panel.begin { resp in
            guard resp == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in self.load(urls: urls) }
        }
    }

    func copyResult() {
        guard let img = outputImage else { return }
        Clipboard.copy(image: img, png: pngData)
    }

    func save() {
        guard let data = pngData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(sourceName)-nobg.png"
        NSApp.activate()
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    /// For dragging the result straight into Figma, Finder, VS Code, etc.
    func tempFileURL() -> URL? {
        guard let data = pngData else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(sourceName)-nobg.png")
        try? data.write(to: url)
        return url
    }

    func reset() { generation += 1; isWorking = false; method = nil; input = nil; lifted = nil; output = nil; error = nil; showOriginal = false; batch = [] }
}
