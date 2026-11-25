import SwiftUI
import AppKit

/// Keeps the latest macOS screenshot (⇧⌘3 / ⇧⌘4 / ⇧⌘5 saved to disk, or copied with ⌃) in memory,
/// so it's one click away in the dropdown: copy, drag out, remove background, convert.
@MainActor
final class ScreenshotKeeper: ObservableObject {
    static let shared = ScreenshotKeeper()

    struct Shot {
        let image: NSImage
        let url: URL?          // nil when it only went to the clipboard
        let date: Date
    }

    @Published private(set) var last: Shot?

    private var query: NSMetadataQuery?
    private var startedAt = Date()
    private var pasteboardTimer: Timer?
    private var folderWatch: DispatchSourceFileSystemObject?

    /// Where ⇧⌘3/4/5 save — System Settings › Screenshot › Options › Save to.
    static var screenshotFolder: URL {
        if let p = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// macOS tags each screenshot file with this extended attribute — independent of language or file name.
    nonisolated static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    /// Spotlight can be off or exclude the folder — also watch the folder itself.
    private func watchFolder() {
        let dir = Self.screenshotFolder
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler {
            // The file appears a moment before it's fully written.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Task { @MainActor in ScreenshotKeeper.shared.scanFolder() }
            }
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        folderWatch = src
    }

    private func scanFolder() {
        let dir = Self.screenshotFolder
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                        options: [.skipsHiddenFiles]) else { return }
        let newest = files
            .compactMap { u -> (URL, Date)? in
                guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let d = v.creationDate, d > startedAt.addingTimeInterval(-86_400) else { return nil }
                return (u, d)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            .first { Self.isScreenshot($0.0) }
        guard let (url, date) = newest else { return }
        if let cur = last, cur.date >= date { return }
        guard let img = NSImage(contentsOf: url) else { return }
        last = Shot(image: img, url: url, date: date)
    }
    private var lastChange = NSPasteboard.general.changeCount

    func start() {
        startedAt = Date()
        // Spotlight tags every screenshot macOS saves (kMDItemIsScreenCapture), wherever it's saved.
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { _ in
            Task { @MainActor in ScreenshotKeeper.shared.refresh(initial: true) }
        }
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { _ in
            Task { @MainActor in ScreenshotKeeper.shared.refresh(initial: false) }
        }
        q.start()
        query = q

        watchFolder()
        scanFolder()

        // ⌃⇧⌘3 / ⌃⇧⌘4 put the screenshot on the clipboard only.
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in ScreenshotKeeper.shared.checkPasteboard() }
        }
    }

    private func refresh(initial: Bool) {
        guard let q = query else { return }
        q.disableUpdates(); defer { q.enableUpdates() }
        guard q.resultCount > 0, let item = q.result(at: 0) as? NSMetadataItem,
              let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return }
        let url = URL(fileURLWithPath: path)
        let date = (item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date) ?? Date()
        if let cur = last, cur.date >= date { return }
        // At launch, remember the most recent one too (from the last day), so the row isn't empty.
        if initial && Date().timeIntervalSince(date) > 86_400 { return }
        guard let img = NSImage(contentsOf: url) else { return }
        last = Shot(image: img, url: url, date: date)
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        // Screenshot tool writes PNG/TIFF image data and no file URL; ignore fdev's own copies.
        guard Clipboard.lastOwnChange != pb.changeCount,
              pb.types?.contains(.fileURL) != true,
              pb.availableType(from: [.png, .tiff]) != nil,
              let img = NSImage(pasteboard: pb) else { return }
        last = Shot(image: img, url: nil, date: Date())
    }

    // MARK: Actions

    var fileURL: URL? {
        if let u = last?.url, FileManager.default.fileExists(atPath: u.path) { return u }
        guard let img = last?.image, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Screenshot.png")
        try? png.write(to: u)
        return u
    }

    func copy() {
        guard let img = last?.image else { return }
        Clipboard.copy(image: img, png: nil)
    }

    func open(in target: DropTarget) {
        guard let u = fileURL else { return }
        target.receive([u])
    }

    func reveal() { if let u = last?.url { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
    func clear() { last = nil }
}

/// "Last screenshot" row at the top of the dropdown.
struct LastScreenshotRow: View {
    @ObservedObject private var keeper = ScreenshotKeeper.shared

    var body: some View {
        if let shot = keeper.last {
            VStack(alignment: .leading, spacing: 2) {
                MenuHeader("Last screenshot")
                HStack(spacing: 10) {
                    Image(nsImage: shot.image)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .onDrag { keeper.fileURL.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
                        .help("Drag into Figma, Slack, your editor…")
                        .accessibilityLabel("Last screenshot")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shot.url?.deletingPathExtension().lastPathComponent ?? "Clipboard screenshot")
                            .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Text("\(Int(shot.image.size.width))×\(Int(shot.image.size.height)) · \(shot.date.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    action("doc.on.doc", "Copy image") { keeper.copy() }
                    action(Tool.background.icon, "Remove background") { keeper.open(in: .background) }
                    action(Tool.image.icon, "Convert image") { keeper.open(in: .convert) }
                    Menu {
                        if shot.url != nil { Button("Show in Finder") { keeper.reveal() } }
                        Button("Forget") { keeper.clear() }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("More")
                }
                .padding(.horizontal, Metrics.inset)
                .padding(.vertical, 4)
                MenuDivider()
            }
        }
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label).accessibilityLabel(label)
    }
}
