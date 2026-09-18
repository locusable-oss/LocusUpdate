import Foundation

public struct UpdateChecker: Sendable {
    public var networkChecksEnabled: Bool
    public var useCache: Bool
    public var cache: DetectionCache

    public init(
        networkChecksEnabled: Bool = true,
        useCache: Bool = true,
        cache: DetectionCache = DetectionCache()
    ) {
        self.networkChecksEnabled = networkChecksEnabled
        self.useCache = useCache
        self.cache = cache
    }

    /// Cache hit → reuse. Otherwise Sparkle → GitHub → vendor, then semver.
    /// `limit` bounds network probes only. Apps with no feed are still returned.
    /// Apps past the probe budget are omitted so the caller can keep their previous status.
    public func evaluate(apps: [InstalledApp], limit: Int = 40) async -> [AppVersionStatus] {
        var entries = useCache ? cache.load() : [:]
        var out: [AppVersionStatus] = []
        var dirty = false
        var probes = 0
        let budget = max(0, limit)

        for app in apps {
            if useCache, let hit = cache.cachedStatus(for: app, entries: entries) {
                out.append(hit)
                continue
            }

            if !networkChecksEnabled {
                out.append(AppVersionStatus(
                    app: app,
                    remote: nil,
                    isOutdated: false,
                    note: "network checks off"
                ))
                continue
            }

            if !Self.hasProbeTarget(app) {
                let status = AppVersionStatus(app: app, remote: nil, isOutdated: false, note: "no feed mapped")
                out.append(status)
                if useCache {
                    cache.upsert(status: status, into: &entries)
                    dirty = true
                }
                continue
            }

            if probes >= budget {
                continue
            }
            probes += 1

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

    /// Local plist read only. True when Sparkle, GitHub, or a vendor homepage can be tried.
    static func hasProbeTarget(_ app: InstalledApp) -> Bool {
        if SparkleProbe.feedURL(fromBundle: app.bundleURL) != nil { return true }
        if GitHubReleasesProbe.repo(fromBundle: app.bundleURL) != nil { return true }
        if VendorPageProbe.homepage(fromBundle: app.bundleURL) != nil { return true }
        return false
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
