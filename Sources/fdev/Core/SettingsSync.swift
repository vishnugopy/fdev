import Foundation
import AppKit

/// Syncs fdev's settings across Macs through iCloud Drive (iCloud Drive/fdev/settings.plist).
/// Apple's iCloud key-value store needs a paid developer signing identity; iCloud Drive doesn't,
/// and macOS syncs the file for us. Last writer wins, by timestamp.
@MainActor
final class SettingsSync: ObservableObject {
    static let shared = SettingsSync()

    /// Everything worth carrying between Macs: shortcuts, wheel, pop-up, tool settings, color history…
    static let syncedKeys = [
        "toast.enabled", "toast.duration", "toast.position",
        "color.hexLowercase", "color.autoCopy", "color.autoCopyFormat", "colorHistory.v1",
        "tools.hidden", "shortcuts.disabled", "shortcuts.custom",
        "wheel.tools", "wheel.hold",
        "units.base", "units.px",
        "fluid.minSize", "fluid.maxSize", "fluid.minVW", "fluid.maxVW",
        "contrast.fg", "contrast.bg", "shadow.layers", "bg.crop",
    ]

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "sync.enabled")   // per-Mac, never synced
            if enabled { start() } else { stop() }
        }
    }
    @Published var lastSync: Date?
    @Published var lastSource: String?
    @Published var error: String?

    private var applying = false
    private var lastWritten: Data?
    private var lastSeenModified: Date?
    private var poll: Timer?
    private var debounce: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/fdev", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("settings.plist") }
    static var iCloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path)
    }

    init() {
        enabled = UserDefaults.standard.object(forKey: "sync.enabled") as? Bool ?? Self.iCloudDriveAvailable
    }

    func start() {
        guard enabled else { return }
        guard Self.iCloudDriveAvailable else { error = "iCloud Drive is off on this Mac."; return }
        error = nil
        pull()                                   // take newer settings from other Macs first
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in SettingsSync.shared.scheduleUpload() }
            }
        }
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in SettingsSync.shared.pull() }
        }
        scheduleUpload()
    }

    func stop() {
        poll?.invalidate(); poll = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func syncNow() { pull(); push(force: true) }

    // MARK: Upload

    private func scheduleUpload() {
        guard enabled, !applying else { return }
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { push() }
        }
    }

    private func snapshot() -> [String: Any] {
        var values: [String: Any] = [:]
        for k in Self.syncedKeys { if let v = UserDefaults.standard.object(forKey: k) { values[k] = v } }
        return values
    }

    private func push(force: Bool = false) {
        guard enabled, !applying else { return }
        let values = snapshot()
        guard let valuesData = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        else { return }
        if !force, valuesData == lastWritten { return }     // nothing changed
        let doc: [String: Any] = [
            "values": values,
            "updatedAt": Date(),
            "device": Host.current().localizedName ?? "Mac",
        ]
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: doc, format: .xml, options: 0)
            try data.write(to: Self.file, options: .atomic)
            lastWritten = valuesData
            lastSeenModified = modified()
            lastSync = Date(); lastSource = "this Mac"; error = nil
        } catch {
            self.error = "Couldn't write to iCloud Drive: \(error.localizedDescription)"
        }
    }

    // MARK: Download

    private func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: Self.file.path))?[.modificationDate] as? Date
    }

    func pull() {
        guard enabled, let mod = modified(), mod != lastSeenModified else { return }
        lastSeenModified = mod
        guard let data = try? Data(contentsOf: Self.file),
              let doc = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let values = doc["values"] as? [String: Any] else { return }
        let valuesData = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        guard valuesData != lastWritten else { return }      // it's our own write

        applying = true
        for k in Self.syncedKeys {
            if let v = values[k] { UserDefaults.standard.set(v, forKey: k) }
            else { UserDefaults.standard.removeObject(forKey: k) }
        }
        lastWritten = valuesData
        AppSettings.shared.load()
        ColorStore.shared.reload()
        ShadowModel.shared.reload()
        applying = false

        lastSync = Date()
        lastSource = doc["device"] as? String
    }
}
