import Foundation

/// Disk cache of probe results keyed by bundleID + shortVersion + Info.plist mtime.
/// Skips re-probe when the installed app fingerprint is unchanged.
public struct DetectionCache: Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var bundleID: String
        public var shortVersion: String
        public var contentModTime: TimeInterval
        public var remoteVersion: String?
        public var remoteSource: String?
        public var remoteInfoURL: String?
        public var isOutdated: Bool
        public var note: String?
        public var checkedAt: Date

        public init(
            bundleID: String,
            shortVersion: String,
            contentModTime: TimeInterval,
            remoteVersion: String? = nil,
            remoteSource: String? = nil,
            remoteInfoURL: String? = nil,
            isOutdated: Bool,
            note: String? = nil,
            checkedAt: Date = Date()
        ) {
            self.bundleID = bundleID
            self.shortVersion = shortVersion
            self.contentModTime = contentModTime
            self.remoteVersion = remoteVersion
            self.remoteSource = remoteSource
            self.remoteInfoURL = remoteInfoURL
            self.isOutdated = isOutdated
            self.note = note
            self.checkedAt = checkedAt
        }

        public func toStatus(app: InstalledApp) -> AppVersionStatus {
            let remote: RemoteVersion?
            if let v = remoteVersion, let srcRaw = remoteSource, let src = VersionSource(rawValue: srcRaw) {
                let url = remoteInfoURL.flatMap(URL.init(string:))
                remote = RemoteVersion(version: v, source: src, infoURL: url)
            } else if let v = remoteVersion {
                let url = remoteInfoURL.flatMap(URL.init(string:))
                remote = RemoteVersion(version: v, source: .unknown, infoURL: url)
            } else {
                remote = nil
            }
            return AppVersionStatus(app: app, remote: remote, isOutdated: isOutdated, note: note)
        }

        public static func from(status: AppVersionStatus, contentModTime: TimeInterval) -> Entry {
            Entry(
                bundleID: status.app.bundleIdentifier,
                shortVersion: status.app.shortVersion,
                contentModTime: contentModTime,
                remoteVersion: status.remote?.version,
                remoteSource: status.remote?.source.rawValue,
                remoteInfoURL: status.remote?.infoURL?.absoluteString,
                isOutdated: status.isOutdated,
                note: status.note,
                checkedAt: Date()
            )
        }
    }

    private struct Store: Codable {
        var entries: [String: Entry]
    }

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL()
        }
    }

    public static func defaultFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("LocusUpdate", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("detection-cache.json")
    }

    /// Fingerprint mtime: Info.plist modification date (seconds since reference).
    public static func contentModTime(for bundleURL: URL) -> TimeInterval {
        let info = bundleURL.appendingPathComponent("Contents/Info.plist")
        let values = try? info.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }


    public func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let store = try? decoder.decode(Store.self, from: data) else { return [:] }
        return store.entries
    }


    public func save(_ entries: [String: Entry]) {
        let store = Store(entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(store) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    /// Identity is bundle id + path so two copies of the same app do not share one cache slot.
    /// Falls back to a legacy bundle-id key written before that split.
    public static func cacheKey(for app: InstalledApp) -> String {
        app.id
    }

    public func cachedStatus(for app: InstalledApp, entries: [String: Entry]) -> AppVersionStatus? {
        let mtime = Self.contentModTime(for: app.bundleURL)
        let entry = entries[Self.cacheKey(for: app)] ?? entries[app.bundleIdentifier]
        guard let entry,
              entry.bundleID == app.bundleIdentifier,
              entry.shortVersion == app.shortVersion,
              abs(entry.contentModTime - mtime) < 0.5 else {
            return nil
        }
        return entry.toStatus(app: app)
    }

    public func upsert(status: AppVersionStatus, into entries: inout [String: Entry]) {
        let mtime = Self.contentModTime(for: status.app.bundleURL)
        let key = Self.cacheKey(for: status.app)
        entries[key] = Entry.from(status: status, contentModTime: mtime)
        if key != status.app.bundleIdentifier {
            entries.removeValue(forKey: status.app.bundleIdentifier)
        }
    }
}
