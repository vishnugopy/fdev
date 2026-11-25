import Foundation

/// The public Google Fonts catalog (no API key). Downloaded once, cached for 7 days.
actor GoogleFonts {
    static let shared = GoogleFonts()

    struct Family: Codable, Sendable {
        let family: String
        let category: String?
    }
    private struct Metadata: Decodable { let familyMetadataList: [Family] }

    private var index: [String: Family]?

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.fdev.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("google-fonts.json")
    }

    /// Returns the matching Google family, nil if not on Google Fonts. Throws if the catalog can't load.
    func match(_ font: DetectedFont) async throws -> Family? {
        let idx = try await loadIndex()
        var candidates = [font.family]
        if let ps = font.postScriptName {
            candidates.append(String(ps.split(separator: "-").first ?? ""))
        }
        for c in candidates {
            var key = Self.norm(c)
            if let hit = idx[key] { return hit }
            for suffix in ["variable", "vf", "web", "webfont"] where key.hasSuffix(suffix) {
                key.removeLast(suffix.count)
                if let hit = idx[key] { return hit }
            }
        }
        return nil
    }

    private func loadIndex() async throws -> [String: Family] {
        if let index { return index }
        var families: [Family]?

        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 7 * 86_400,
           let data = try? Data(contentsOf: cacheURL) {
            families = try? JSONDecoder().decode([Family].self, from: data)
        }

        if families == nil {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "https://fonts.google.com/metadata/fonts")!)
            var body = data
            // The response starts with an anti-XSSI prefix: )]}'
            if let nl = body.firstIndex(of: UInt8(ascii: "{")) { body = body[nl...] }
            let list = try JSONDecoder().decode(Metadata.self, from: body).familyMetadataList
            families = list
            try? JSONEncoder().encode(list).write(to: cacheURL)
        }

        let built = Dictionary((families ?? []).map { (Self.norm($0.family), $0) }, uniquingKeysWith: { a, _ in a })
        index = built
        return built
    }

    static func norm(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func specimenURL(_ family: String) -> URL {
        URL(string: "https://fonts.google.com/specimen/" +
            (family.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? family))!
    }

    static func importCSS(_ family: String, weight: Int?) -> String {
        let fam = family.replacingOccurrences(of: " ", with: "+")
        let w = weight.map { ":wght@\($0)" } ?? ""
        return "@import url('https://fonts.googleapis.com/css2?family=\(fam)\(w)&display=swap');"
    }

    static func generic(for category: String?) -> String {
        switch category?.lowercased() {
        case "serif": "serif"
        case "monospace": "monospace"
        case "handwriting": "cursive"
        default: "sans-serif"
        }
    }
}
