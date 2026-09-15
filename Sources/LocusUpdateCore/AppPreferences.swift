import Foundation
import Combine

/// Persisted user settings (UserDefaults). Display name in UI: LocusUpdate.
@MainActor
public final class AppPreferences: ObservableObject {
    public static let shared = AppPreferences()

    private let defaults: UserDefaults
    private enum Key {
        static let ignoredBundleIDs = "locusupdate.ignoredBundleIDs"
        static let pinnedVersions = "locusupdate.pinnedVersions"
        static let scanPaths = "locusupdate.scanPaths"
        static let scanIntervalMinutes = "locusupdate.scanIntervalMinutes"
        static let notificationsEnabled = "locusupdate.notificationsEnabled"
        static let networkChecksEnabled = "locusupdate.networkChecksEnabled"
    }

    @Published public var ignoredBundleIDs: Set<String> {
        didSet { defaults.set(Array(ignoredBundleIDs).sorted(), forKey: Key.ignoredBundleIDs) }
    }

    /// bundleID → pinned/fixed version string the user accepts (excluded from outdated).
    @Published public var pinnedVersions: [String: String] {
        didSet { defaults.set(pinnedVersions, forKey: Key.pinnedVersions) }
    }

    @Published public var scanPaths: [String] {
        didSet { defaults.set(scanPaths, forKey: Key.scanPaths) }
    }

    /// Background scan interval in minutes. Minimum 15; 0 disables timed scans.
    @Published public var scanIntervalMinutes: Int {
        didSet { defaults.set(scanIntervalMinutes, forKey: Key.scanIntervalMinutes) }
    }

    @Published public var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    /// When false, UpdateChecker skips network probes and uses cache / local-only notes.
    @Published public var networkChecksEnabled: Bool {
        didSet { defaults.set(networkChecksEnabled, forKey: Key.networkChecksEnabled) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let ignored = defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? []
        self.ignoredBundleIDs = Set(ignored)

        if let pinned = defaults.dictionary(forKey: Key.pinnedVersions) as? [String: String] {
            self.pinnedVersions = pinned
        } else {
            self.pinnedVersions = [:]
        }

        if let paths = defaults.stringArray(forKey: Key.scanPaths), !paths.isEmpty {
            self.scanPaths = paths
        } else {
            self.scanPaths = Self.defaultScanPaths()
        }

        let interval = defaults.object(forKey: Key.scanIntervalMinutes) as? Int
        self.scanIntervalMinutes = interval ?? 360

        if defaults.object(forKey: Key.notificationsEnabled) == nil {
            self.notificationsEnabled = true
        } else {
            self.notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        }

        if defaults.object(forKey: Key.networkChecksEnabled) == nil {
            self.networkChecksEnabled = true
        } else {
            self.networkChecksEnabled = defaults.bool(forKey: Key.networkChecksEnabled)
        }
    }

    public static func defaultScanPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications", "\(home)/Applications"]
    }

    public func scanRootURLs() -> [URL] {
        scanPaths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    public func isIgnored(bundleID: String) -> Bool {
        ignoredBundleIDs.contains(bundleID)
    }

    public func ignore(bundleID: String) {
        ignoredBundleIDs.insert(bundleID)
    }

    public func unignore(bundleID: String) {
        ignoredBundleIDs.remove(bundleID)
    }

    public func pin(bundleID: String, version: String) {
        var next = pinnedVersions
        next[bundleID] = version
        pinnedVersions = next
    }

    public func unpin(bundleID: String) {
        var next = pinnedVersions
        next.removeValue(forKey: bundleID)
        pinnedVersions = next
    }

    public func pinnedVersion(for bundleID: String) -> String? {
        pinnedVersions[bundleID]
    }

    /// Outdated for UI/summary: remote newer, not ignored, and not pinned.
    public func isEffectivelyOutdated(_ status: AppVersionStatus) -> Bool {
        guard status.isOutdated else { return false }
        guard !isIgnored(bundleID: status.app.bundleIdentifier) else { return false }
        if pinnedVersions[status.app.bundleIdentifier] != nil { return false }
        return true
    }
}
