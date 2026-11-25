import AppKit
import ImageIO
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable {
    case avif = "AVIF", jpeg = "JPEG", png = "PNG", heic = "HEIC"
    var id: String { rawValue }
    var type: UTType {
        switch self {
        case .avif: UTType("public.avif") ?? .png
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        }
    }
    var ext: String { rawValue.lowercased() == "jpeg" ? "jpg" : rawValue.lowercased() }
    var mime: String { type.preferredMIMEType ?? "image/\(rawValue.lowercased())" }
    var lossy: Bool { self != .png }
}

/// Re-encodes images with ImageIO. Strips metadata (EXIF/GPS), applies orientation, optional resize.
enum ImageConverter {
    struct Failure: LocalizedError { let errorDescription: String? }

    static func pixelSize(of data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }

    static func convert(_ data: Data, to format: OutputFormat, quality: Double, maxDimension: Int) throws -> (Data, CGSize) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let size = pixelSize(of: data) else {
            throw Failure(errorDescription: "Can't read this image.")
        }
        let longest = Int(max(size.width, size.height))
        let target = maxDimension > 0 ? min(maxDimension, longest) : longest
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // bake in EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: target,
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw Failure(errorDescription: "Couldn't decode the image.")
        }
        if format == .jpeg, image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst {
            image = flattened(image) ?? image   // JPEG has no alpha: put it on white, not black
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, format.type.identifier as CFString, 1, nil) else {
            throw Failure(errorDescription: "\(format.rawValue) isn't supported on this Mac.")
        }
        var props: [CFString: Any] = [:]
        if format.lossy { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure(errorDescription: "Encoding failed.") }
        return (out as Data, CGSize(width: image.width, height: image.height))
    }

    private static func flattened(_ img: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let r = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(.white); ctx.fill(r); ctx.draw(img, in: r)
        return ctx.makeImage()
    }
}

@MainActor
final class ImageConvertModel: ObservableObject {
    static let shared = ImageConvertModel()

    @Published var source: Data?
    @Published var sourceSize: CGSize?
    @Published var output: Data?
    @Published var outputSize: CGSize?
    @Published var isWorking = false
    @Published var error: String?
    @Published var format: OutputFormat = .avif { didSet { convert() } }
    @Published var quality: Double = 0.75 { didSet { scheduleConvert() } }
    @Published var maxDimension: Int = 0 { didSet { convert() } }
    var name = "image"

    private var job: Task<Void, Never>?
    private var debounce: Task<Void, Never>?

    var previewImage: NSImage? { (output ?? source).flatMap { NSImage(data: $0) } }

    var savingsText: String? {
        guard let s = source?.count, let o = output?.count, s > 0 else { return nil }
        let pct = Int(((1 - Double(o) / Double(s)) * 100).rounded())
        return pct >= 0 ? "−\(pct)%" : "+\(-pct)%"
    }

    func load(_ data: Data, name: String) {
        guard let size = ImageConverter.pixelSize(of: data) else { error = "That isn't an image."; return }
        source = data; sourceSize = size; self.name = name; error = nil
        convert()
    }

    func load(url: URL) {
        guard let d = try? Data(contentsOf: url) else { error = "Couldn't read the file."; return }
        load(d, name: url.deletingPathExtension().lastPathComponent)
    }

    func paste() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let u = urls.first { load(url: u); return }
        for t in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")] {
            if let d = pb.data(forType: t) { load(d, name: "pasted"); return }
        }
        error = "No image on the clipboard."
    }

    func openFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        NSApp.activate()
        p.begin { r in
            guard r == .OK, let u = p.url else { return }
            Task { @MainActor in self.load(url: u) }
        }
    }

    private func scheduleConvert() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            if !Task.isCancelled { convert() }
        }
    }

    func convert() {
        guard let src = source else { return }
        job?.cancel()
        isWorking = true
        let (f, q, m) = (format, quality, maxDimension)
        job = Task.detached(priority: .userInitiated) {
            let result = Result { try ImageConverter.convert(src, to: f, quality: q, maxDimension: m) }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                self.isWorking = false
                switch result {
                case .success(let (d, s)): self.output = d; self.outputSize = s; self.error = nil
                case .failure(let e): self.output = nil; self.error = e.localizedDescription
                }
            }
        }
    }

    var fileName: String { "\(name).\(format.ext)" }

    func save() {
        guard let d = output else { return }
        let p = NSSavePanel()
        p.allowedContentTypes = [format.type]
        p.nameFieldStringValue = fileName
        NSApp.activate()
        p.begin { r in if r == .OK, let u = p.url { try? d.write(to: u) } }
    }

    func copyDataURI() {
        guard let d = output else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("data:\(format.mime);base64,\(d.base64EncodedString())", forType: .string)
        CopyHUD.shared.show(text: "Data URI · \(Self.bytes(d.count))", swatch: nil, symbol: "link")
    }

    func copyImage() {
        guard let d = output, let img = NSImage(data: d) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
        pb.setData(d, forType: NSPasteboard.PasteboardType(format.type.identifier))
        CopyHUD.shared.show(text: "\(format.rawValue) copied", swatch: nil, symbol: "photo")
    }

    func tempFileURL() -> URL? {
        guard let d = output else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? d.write(to: u)
        return u
    }

    func reset() { job?.cancel(); source = nil; output = nil; sourceSize = nil; outputSize = nil; error = nil; isWorking = false }

    static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
