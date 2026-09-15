import Foundation

public struct UpdateChecker: Sendable {
    public var networkChecksEnabled: Bool
    public var useCache: Bool

    public init(networkChecksEnabled: Bool = true, useCache: Bool = true) {
        self.networkChecksEnabled = networkChecksEnabled
        self.useCache = useCache
    }

    /// For each installed app: cache hit → reuse; else Sparkle → GitHub → vendor; then semver outdated check.
    public func evaluate(apps: [InstalledApp], limit: Int = 40) async -> [AppVersionStatus] {
        let cache = DetectionCache()
        var entries = useCache ? cache.load() : [:]
        var out: [AppVersionStatus] = []
        var dirty = false

        for app in apps.prefix(limit) {
            if useCache, let hit = cache.cachedStatus(for: app, entries: entries) {
                out.append(hit)
                continue
            }

            if !networkChecksEnabled {
                let status = AppVersionStatus(
                    app: app,
                    remote: nil,
                    isOutdated: false,
                    note: "network checks off"
                )
                out.append(status)
                continue
            }

            let status = await evaluateOne(app)
            out.append(status)
            if useCache {
                cache.upsert(status: status, into: &entries)
                dirty = true
            }
        }

        if dirty {
            cache.save(entries)
        }
        return out
    }

    private func evaluateOne(_ app: InstalledApp) async -> AppVersionStatus {
        if let feed = SparkleProbe.feedURL(fromBundle: app.bundleURL),
           let remote = await SparkleProbe.latestVersion(feedURL: feed) {
            let old = SemanticVersion.isOutdated(local: app.shortVersion, remote: remote.version)
            return AppVersionStatus(app: app, remote: remote, isOutdated: old)
        }
        if let repo = GitHubReleasesProbe.repo(fromBundle: app.bundleURL),
           let remote = await GitHubReleasesProbe.latestRelease(owner: repo.owner, repo: repo.repo) {
            let old = SemanticVersion.isOutdated(local: app.shortVersion, remote: remote.version)
            return AppVersionStatus(app: app, remote: remote, isOutdated: old)
        }
        if let home = VendorPageProbe.homepage(fromBundle: app.bundleURL),
           let remote = await VendorPageProbe.latestVersion(homepage: home) {
            let old = SemanticVersion.isOutdated(local: app.shortVersion, remote: remote.version)
            return AppVersionStatus(app: app, remote: remote, isOutdated: old, note: "vendor heuristic")
        }
        return AppVersionStatus(app: app, remote: nil, isOutdated: false, note: "no feed mapped")
    }
}
