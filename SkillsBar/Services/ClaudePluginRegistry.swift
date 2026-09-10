import Foundation

struct ClaudePluginRegistry {
    let home: String

    /// The cache also contains old and uninstalled versions. Only registry entries are installed.
    func installedPluginPaths() -> [String] {
        let path = (home as NSString).appendingPathComponent(".claude/plugins/installed_plugins.json")
        guard let data = FileManager.default.contents(atPath: path),
              let registry = try? JSONDecoder().decode(Registry.self, from: data) else { return [] }

        var seenPaths: Set<String> = []
        return registry.plugins.keys.sorted().compactMap { identifier in
            // Show one copy per plugin in the library, preferring its user installation.
            let installations = registry.plugins[identifier, default: []].sorted {
                if ($0.scope == "user") != ($1.scope == "user") {
                    return $0.scope == "user"
                }
                if $0.updateDate != $1.updateDate {
                    return $0.updateDate > $1.updateDate
                }
                return $0.installPath < $1.installPath
            }

            for installation in installations {
                let expandedPath = (installation.installPath as NSString).expandingTildeInPath
                guard (expandedPath as NSString).isAbsolutePath else { continue }
                let root = URL(fileURLWithPath: expandedPath).resolvingSymlinksInPath().path
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                return seenPaths.insert(root).inserted ? root : nil
            }
            return nil
        }
    }

    private struct Registry: Decodable {
        let plugins: [String: [Installation]]
    }

    private struct Installation: Decodable {
        let installPath: String
        let scope: String?
        let lastUpdated: String?
        let installedAt: String?

        var updateDate: Date {
            guard let timestamp = lastUpdated ?? installedAt else { return .distantPast }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions.insert(.withFractionalSeconds)
            if let date = formatter.date(from: timestamp) { return date }
            formatter.formatOptions.remove(.withFractionalSeconds)
            return formatter.date(from: timestamp) ?? .distantPast
        }
    }
}
