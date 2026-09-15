import XCTest
@testable import LocusUpdateCore

final class PlistVersionReaderTests: XCTestCase {
    func testReadMissingBundleReturnsNil() throws {
        let url = URL(fileURLWithPath: "/tmp/DefinitelyMissingApp-\(UUID().uuidString).app")
        XCTAssertNil(PlistVersionReader.read(bundleURL: url))
    }
}
