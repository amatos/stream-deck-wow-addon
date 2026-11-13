import Foundation

/// The WoW install that owns a running client: its root folder, product and version.
public struct WoWInstall: Equatable, Sendable {
    public var root: URL
    public var product: String
    public var version: String

    public init(root: URL, product: String, version: String) {
        self.root = root
        self.product = product
        self.version = version
    }

    /// CascLib storage path: "<root>*<product>".
    public var storagePath: String { root.path + "*" + product }

    public static let defaultRoot = URL(fileURLWithPath: "/Applications/World of Warcraft")

    /// Finds the install for a client app bundle (".../_forever_/World of Warcraft.app"),
    /// or the default location. `product` prefers the flavour folder's entry.
    public static func locate(appBundle: URL?, fileManager: FileManager = .default) -> WoWInstall? {
        var candidates: [(root: URL, flavour: String?)] = []
        if let app = appBundle {
            let flavourDir = app.deletingLastPathComponent()
            candidates.append((flavourDir.deletingLastPathComponent(), flavourDir.lastPathComponent))
        }
        candidates.append((defaultRoot, nil))
        for c in candidates {
            let info = c.root.appendingPathComponent(".build.info")
            guard let text = try? String(contentsOf: info, encoding: .utf8) else { continue }
            let entries = BuildInfo.parse(text).filter { $0["Active"] == "1" }
            let flavourProduct = c.flavour.flatMap(BuildInfo.product(forFlavourFolder:))
            let entry = entries.first { $0["Product"] == flavourProduct } ?? entries.first
            if let entry, let product = entry["Product"], !product.isEmpty {
                return WoWInstall(root: c.root, product: product, version: entry["Version"] ?? "unknown")
            }
        }
        return nil
    }
}

/// Parses Blizzard's ".build.info" table: a "Name!TYPE:size|..." header, then rows.
public enum BuildInfo {
    public static func parse(_ text: String) -> [[String: String]] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard let header = lines.first else { return [] }
        let names = header.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0.split(separator: "!").first ?? "")
        }
        return lines.dropFirst().map { line in
            let values = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            var row: [String: String] = [:]
            for (i, name) in names.enumerated() where i < values.count { row[name] = values[i] }
            return row
        }
    }

    /// Product codes for known flavour folders ("_forever_" -> "wowf").
    public static func product(forFlavourFolder folder: String) -> String? {
        switch folder {
        case "_forever_": return "wowf"
        case "_retail_": return "wow"
        case "_classic_": return "wow_classic"
        case "_classic_era_": return "wow_classic_era"
        case "_ptr_": return "wowt"
        case "_beta_": return "wow_beta"
        default: return nil
        }
    }
}
