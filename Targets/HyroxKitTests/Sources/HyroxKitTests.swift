import XCTest
@testable import HyroxKit

final class HyroxKitTests: XCTestCase {
    func testVersion() throws {
        XCTAssertEqual(HyroxKit.version, "0.1.0")
    }
}
