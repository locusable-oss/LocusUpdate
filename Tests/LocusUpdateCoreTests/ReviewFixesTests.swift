import XCTest
@testable import LocusUpdateCore

final class SemanticVersionReviewTests: XCTestCase {
    func testHugeNumericComponentDoesNotCollapse() {
        let huge = "999999999999999999999"
        XCTAssertEqual(SemanticVersion.compare("1", huge), .orderedAscending)
        XCTAssertEqual(SemanticVersion.compare(huge, "1"), .orderedDescending)
        XCTAssertTrue(SemanticVersion.isOutdated(local: "1.0", remote: huge))
        XCTAssertFalse(SemanticVersion.isOutdated(local: huge, remote: "1"))
    }

    func testReleaseIsNewerThanSameNumberPrerelease() {
        XCTAssertEqual(SemanticVersion.compare("1.2.3", "1.2.3-beta"), .orderedDescending)
        XCTAssertEqual(SemanticVersion.compare("1.2.3-beta", "1.2.3"), .orderedAscending)
        XCTAssertFalse(SemanticVersion.isOutdated(local: "1.2.3", remote: "1.2.3b1"))
        XCTAssertTrue(SemanticVersion.isOutdated(local: "1.2.3-beta", remote: "1.2.3"))
    }

    func testPaddingAndLeadingV() {
        XCTAssertEqual(SemanticVersion.compare("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(SemanticVersion.compare("v1.2.3", "1.2.3"), .orderedSame)
        XCTAssertEqual(SemanticVersion.compare("1.9", "1.10"), .orderedAscending)
        XCTAssertEqual(SemanticVersion.compare("01.2", "1.2"), .orderedSame)
    }

    func testMissingVersionIsNotOutdated() {
        XCTAssertFalse(SemanticVersion.isOutdated(local: "—", remote: "2.0"))
        XCTAssertFalse(SemanticVersion.isOutdated(local: "", remote: "2.0"))
    }
}

final class ProbeSafetyTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocusUpdateProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testVendorHomepageIgnoresArbitraryHTTPSStrings() throws {
        let bundle = try writeApp(name: "Vendor", extra: [
            "NSCrashReporterEmail": "not-a-url",
            "AnalyticsEndpoint": "https://telemetry.example/collect",
            "SUFeedURL": "https://updates.example/appcast.xml",
            "Homepage": "https://vendor.example/download",
        ])
        let home = VendorPageProbe.homepage(fromBundle: bundle)
        XCTAssertEqual(home?.host, "vendor.example")
    }

    func testVendorHomepageNilWhenOnlyTelemetryURL() throws {
        let bundle = try writeApp(name: "Telemetry", extra: [
            "AnalyticsEndpoint": "https://telemetry.example/collect",
            "SUFeedURL": "https://updates.example/appcast.xml",
        ])
        XCTAssertNil(VendorPageProbe.homepage(fromBundle: bundle))
    }

    func testPlausibleVersionsSkipYears() {
        XCTAssertFalse(VendorPageProbe.isPlausibleProductVersion("2026.9"))
        XCTAssertTrue(VendorPageProbe.isPlausibleProductVersion("0.2.0"))
        XCTAssertTrue(VendorPageProbe.isPlausibleProductVersion("14.1.2"))
        XCTAssertFalse(VendorPageProbe.isPublicHTTPSPage(URL(string: "http://vendor.example/app")!))
        XCTAssertFalse(VendorPageProbe.isPublicHTTPSPage(URL(string: "https://127.0.0.1/app")!))
        XCTAssertFalse(VendorPageProbe.isPublicHTTPSPage(URL(string: "https://github.com/a/b")!))
    }

    func testGitHubSegmentRejectsTraversal() {
        XCTAssertNil(GitHubReleasesProbe.sanitizePathSegment("../etc"))
        XCTAssertNil(GitHubReleasesProbe.sanitizePathSegment("owner/repo"))
        XCTAssertNil(GitHubReleasesProbe.sanitizePathSegment(""))
        XCTAssertEqual(GitHubReleasesProbe.sanitizePathSegment("LocusUpdate.git"), "LocusUpdate")
    }

    func testGitHubRepoFromBundle() throws {
        let bundle = try writeApp(name: "GH", extra: [
            "Homepage": "https://github.com/locusable-oss/LocusUpdate.git",
        ])
        let repo = GitHubReleasesProbe.repo(fromBundle: bundle)
        XCTAssertEqual(repo?.owner, "locusable-oss")
        XCTAssertEqual(repo?.repo, "LocusUpdate")
    }

    func testSparkleFeedRejectsNonHTTP() throws {
        let bundle = try writeApp(name: "Feed", extra: [
            "SUFeedURL": "file:///tmp/appcast.xml",
        ])
        XCTAssertNil(SparkleProbe.feedURL(fromBundle: bundle))
    }

    func testSparklePairsBestVersionWithItsNotesURL() {
        let xml = """
        <rss><channel>
        <item>
          <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
          <sparkle:releaseNotesLink>https://example.com/notes/1</sparkle:releaseNotesLink>
          <enclosure url="https://example.com/1.dmg" sparkle:shortVersionString="1.0.0"/>
        </item>
        <item>
          <sparkle:shortVersionString>2.4.1</sparkle:shortVersionString>
          <sparkle:releaseNotesLink>https://example.com/notes/2</sparkle:releaseNotesLink>
          <enclosure url="https://example.com/2.dmg" sparkle:shortVersionString="2.4.1"/>
        </item>
        </channel></rss>
        """
        let parsed = SparkleProbe.parsedRelease(in: xml)
        XCTAssertEqual(parsed?.version, "2.4.1")
        XCTAssertEqual(parsed?.infoURL?.absoluteString, "https://example.com/notes/2")
    }

    func testBrowserURLRejectsFileScheme() {
        let remote = RemoteVersion(version: "1", source: .sparkle, infoURL: URL(string: "file:///tmp/app.dmg"))
        XCTAssertNil(remote.browserURL)
        let page = RemoteVersion(version: "1", source: .githubReleases, infoURL: URL(string: "https://github.com/a/b/releases/tag/v1"))
        XCTAssertEqual(page.browserURL?.host, "github.com")
    }

    func testEvaluateReturnsAppsWithoutFeedsEvenUnderTinyLimit() async throws {
        let apps = try ["A", "B", "C"].map { name in
            let bundle = try writeApp(name: name, extra: [:])
            return InstalledApp(
                name: name,
                bundleIdentifier: "studio.test.\(name)",
                shortVersion: "1.0",
                buildVersion: "1",
                bundleURL: bundle
            )
        }
        let cache = DetectionCache(fileURL: tempDir.appendingPathComponent("c.json"))
        let checker = UpdateChecker(networkChecksEnabled: true, useCache: false, cache: cache)
        let result = await checker.evaluate(apps: apps, limit: 1)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.map(\.note), ["no feed mapped", "no feed mapped", "no feed mapped"])
    }

    func testTwoCopiesDoNotShareCache() throws {
        let firstBundle = try writeApp(name: "CopyA", extra: ["CFBundleShortVersionString": "1.0"])
        let secondBundle = try writeApp(name: "CopyB", extra: ["CFBundleShortVersionString": "2.0"])
        let appA = InstalledApp(name: "Copy", bundleIdentifier: "studio.test.Copy", shortVersion: "1.0", buildVersion: "1", bundleURL: firstBundle)
        let appB = InstalledApp(name: "Copy", bundleIdentifier: "studio.test.Copy", shortVersion: "2.0", buildVersion: "2", bundleURL: secondBundle)
        XCTAssertNotEqual(appA.id, appB.id)
        let cache = DetectionCache(fileURL: tempDir.appendingPathComponent("two.json"))
        var entries: [String: DetectionCache.Entry] = [:]
        cache.upsert(
            status: AppVersionStatus(app: appA, remote: RemoteVersion(version: "9.0", source: .sparkle), isOutdated: true),
            into: &entries
        )
        cache.upsert(
            status: AppVersionStatus(app: appB, remote: RemoteVersion(version: "2.0", source: .githubReleases), isOutdated: false),
            into: &entries
        )
        cache.save(entries)
        let loaded = cache.load()
        XCTAssertEqual(cache.cachedStatus(for: appA, entries: loaded)?.remote?.version, "9.0")
        XCTAssertEqual(cache.cachedStatus(for: appB, entries: loaded)?.remote?.version, "2.0")
        XCTAssertEqual(loaded.count, 2)
    }

    private func writeApp(name: String, extra: [String: Any]) throws -> URL {
        let bundle = tempDir.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = [
            "CFBundleName": name,
            "CFBundleIdentifier": extra["CFBundleIdentifier"] as? String ?? "studio.test.\(name)",
            "CFBundleShortVersionString": extra["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "CFBundleVersion": "1",
        ]
        for (k, v) in extra where !["CFBundleIdentifier", "CFBundleShortVersionString"].contains(k) {
            plist[k] = v
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }
}
