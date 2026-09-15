import Foundation

public struct AppScanner: Sendable {
    public var searchRoots: [URL]

    public init(searchRoots: [URL]? = nil) {
        if let searchRoots {
            self.searchRoots = searchRoots
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.searchRoots = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appendingPathComponent("Applications", isDirectory: true),
            ]
        }
    }

    /// Convenience: build scanner from preference path strings (tilde expanded).
    public init(pathStrings: [String]) {
        self.searchRoots = pathStrings.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
    }

    /// Scans configured roots for `.app` bundles (non-recursive into other apps' Contents).
    public func scanInstalledApps() -> [InstalledApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [InstalledApp] = []

        for root in searchRoots {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for url in entries where url.pathExtension == "app" {
                if let app = PlistVersionReader.read(bundleURL: url) {
                    let key = app.bundleIdentifier + "|" + app.bundleURL.standardizedFileURL.path
                    if seen.insert(key).inserted {
                        result.append(app)
                    }
                }
            }
        }

        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
