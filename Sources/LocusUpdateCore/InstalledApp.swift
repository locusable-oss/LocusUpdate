import Foundation

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public var id: String { bundleIdentifier + "|" + bundleURL.path }
    public let name: String
    public let bundleIdentifier: String
    public let shortVersion: String
    public let buildVersion: String
    public let bundleURL: URL

    public init(
        name: String,
        bundleIdentifier: String,
        shortVersion: String,
        buildVersion: String,
        bundleURL: URL
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
        self.bundleURL = bundleURL
    }
}
