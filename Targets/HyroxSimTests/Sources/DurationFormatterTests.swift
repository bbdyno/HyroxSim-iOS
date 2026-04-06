import XCTest
@testable import HyroxSim

final class DurationFormatterTests: XCTestCase {

    func testHMS() {
        XCTAssertEqual(DurationFormatter.hms(3661), "1:01:01")
        XCTAssertEqual(DurationFormatter.hms(0), "0:00:00")
        XCTAssertEqual(DurationFormatter.hms(59), "0:00:59")
        XCTAssertEqual(DurationFormatter.hms(3600), "1:00:00")
    }

    func testMS() {
        XCTAssertEqual(DurationFormatter.ms(125), "02:05")
        XCTAssertEqual(DurationFormatter.ms(0), "00:00")
        XCTAssertEqual(DurationFormatter.ms(60), "01:00")
    }

    func testPace() {
        XCTAssertEqual(DurationFormatter.pace(342), "5'42\" /km")
        XCTAssertEqual(DurationFormatter.pace(300), "5'00\" /km")
        XCTAssertEqual(DurationFormatter.pace(nil), "—")
        XCTAssertEqual(DurationFormatter.pace(0), "—")
    }
}
