import XCTest
@testable import HyroxKit

final class StationTargetTests: XCTestCase {

    func testDistanceFormatted() {
        XCTAssertEqual(StationTarget.distance(meters: 1000).formatted, "1000 m")
    }

    func testRepsFormatted() {
        XCTAssertEqual(StationTarget.reps(count: 100).formatted, "100 reps")
    }

    func testDurationFormatted() {
        XCTAssertEqual(StationTarget.duration(seconds: 120).formatted, "02:00")
    }

    func testNoneFormatted() {
        XCTAssertEqual(StationTarget.none.formatted, "—")
    }

    func testSmallDistanceFormatted() {
        XCTAssertEqual(StationTarget.distance(meters: 50).formatted, "50 m")
    }

    func testDurationFormattedWithOddSeconds() {
        XCTAssertEqual(StationTarget.duration(seconds: 65).formatted, "01:05")
    }
}
