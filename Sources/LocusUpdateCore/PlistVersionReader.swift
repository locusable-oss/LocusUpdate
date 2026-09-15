import Foundation

public enum PlistVersionReader {
    /// Reads version fields from an `.app` bundle Info.plist.
    public static func read(bundleURL: URL) -> InstalledApp? {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoURL.path) else {
            return nil
        }
        guard let dict = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            return nil
        }

        let bundleId = (dict["CFBundleIdentifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !bundleId.isEmpty else { return nil }

        let displayName =
            (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        let shortVersion = (dict["CFBundleShortVersionString"] as? String) ?? ""
        let buildVersion = (dict["CFBundleVersion"] as? String) ?? ""

        return InstalledApp(
            name: displayName,
            bundleIdentifier: bundleId,
            shortVersion: shortVersion.isEmpty ? "—" : shortVersion,
            buildVersion: buildVersion.isEmpty ? "—" : buildVersion,
            bundleURL: bundleURL.standardizedFileURL
        )
    }
}
