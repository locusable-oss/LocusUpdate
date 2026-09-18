import Foundation

public enum VersionSource: String, Sendable, Equatable {
    case sparkle
    case githubReleases
    case vendorPage
    case unknown
}

public struct RemoteVersion: Sendable, Equatable {
    public let version: String
    public let source: VersionSource
    public let infoURL: URL?

    public init(version: String, source: VersionSource, infoURL: URL? = nil) {
        self.version = version
        self.source = source
        self.infoURL = infoURL
    }

    /// Browser-openable page. Rejects `file:`, custom schemes, and host-less URLs so a crafted feed cannot hand the shell a local path.
    public var browserURL: URL? {
        guard let infoURL else { return nil }
        return Self.httpURL(infoURL)
    }

    public static func httpURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

public struct AppVersionStatus: Identifiable, Sendable, Equatable {
    public var id: String { app.id }
    public let app: InstalledApp
    public let remote: RemoteVersion?
    public let isOutdated: Bool
    public let note: String?

    public init(app: InstalledApp, remote: RemoteVersion?, isOutdated: Bool, note: String? = nil) {
        self.app = app
        self.remote = remote
        self.isOutdated = isOutdated
        self.note = note
    }
}
