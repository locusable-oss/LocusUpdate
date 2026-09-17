import XCTest
@testable import LocusUpdateCore

final class DetectionCacheTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocusUpdateCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testFingerprintSkipWhenUnchanged() throws {
        let bundle = try makeFakeApp(name: "Demo", version: "1.2.3")
        let app = InstalledApp(
            name: "Demo",
            bundleIdentifier: "studio.test.Demo",
            shortVersion: "1.2.3",
            buildVersion: "123",
            bundleURL: bundle
        )
        let cacheURL = tempDir.appendingPathComponent("cache.json")
        let cache = DetectionCache(fileURL: cacheURL)

        var entries: [String: DetectionCache.Entry] = [:]
        let status = AppVersionStatus(
            app: app,
            remote: RemoteVersion(
                version: "1.3.0",
                source: .sparkle,
                infoURL: URL(string: "https://example.com/appcast.xml")
            ),
            isOutdated: true
        )
        cache.upsert(status: status, into: &entries)
        cache.save(entries)

        let loaded = cache.load()
        XCTAssertEqual(loaded.count, 1)
        let hit = cache.cachedStatus(for: app, entries: loaded)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.remote?.version, "1.3.0")
        XCTAssertEqual(hit?.isOutdated, true)
    }

    func testCacheMissWhenVersionChanges() throws {
        let bundle = try makeFakeApp(name: "Demo", version: "1.2.3")
        let appV1 = InstalledApp(
            name: "Demo",
            bundleIdentifier: "studio.test.Demo",
            shortVersion: "1.2.3",
            buildVersion: "123",
            bundleURL: bundle
        )
        let cacheURL = tempDir.appendingPathComponent("cache2.json")
        let cache = DetectionCache(fileURL: cacheURL)
        var entries: [String: DetectionCache.Entry] = [:]
        cache.upsert(
            status: AppVersionStatus(app: appV1, remote: nil, isOutdated: false, note: "no feed"),
            into: &entries
        )
        cache.save(entries)

        let appV2 = InstalledApp(
            name: "Demo",
            bundleIdentifier: "studio.test.Demo",
            shortVersion: "1.2.4",
            buildVersion: "124",
            bundleURL: bundle
        )
        let miss = cache.cachedStatus(for: appV2, entries: cache.load())
        XCTAssertNil(miss)
    }

    func testCacheMissWhenPlistMtimeChanges() throws {
        let bundle = try makeFakeApp(name: "Demo", version: "1.0.0")
        let app = InstalledApp(
            name: "Demo",
            bundleIdentifier: "studio.test.Demo",
            shortVersion: "1.0.0",
            buildVersion: "1",
            bundleURL: bundle
        )
        let cacheURL = tempDir.appendingPathComponent("cache3.json")
        let cache = DetectionCache(fileURL: cacheURL)
        var entries: [String: DetectionCache.Entry] = [:]
        cache.upsert(
            status: AppVersionStatus(
                app: app,
                remote: RemoteVersion(version: "1.0.0", source: .githubReleases, infoURL: nil),
                isOutdated: false
            ),
            into: &entries
        )
        cache.save(entries)
        XCTAssertNotNil(cache.cachedStatus(for: app, entries: cache.load()))

        let info = bundle.appendingPathComponent("Contents/Info.plist")
        // Bump mtime into the future so fingerprint diverges.
        let future = Date(timeIntervalSinceNow: 120)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: info.path)

        let miss = cache.cachedStatus(for: app, entries: cache.load())
        XCTAssertNil(miss)
    }

    func testEmptyCacheLoad() {
        let cacheURL = tempDir.appendingPathComponent("missing.json")
        let cache = DetectionCache(fileURL: cacheURL)
        XCTAssertTrue(cache.load().isEmpty)
    }

    private func makeFakeApp(name: String, version: String) throws -> URL {
        let bundle = tempDir.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleName": name,
            "CFBundleIdentifier": "studio.test.\(name)",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": "1",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }
}
