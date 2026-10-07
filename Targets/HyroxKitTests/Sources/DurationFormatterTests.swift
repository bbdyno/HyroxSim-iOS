//
//  DurationFormatterTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

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

    // MARK: - 극단값 방어 (Double → Int 변환 트랩 회귀 방지)

    func testHMSHandlesExtremeValues() {
        XCTAssertEqual(DurationFormatter.hms(-1), "0:00:00")
        XCTAssertEqual(DurationFormatter.hms(.nan), "0:00:00")
        XCTAssertEqual(DurationFormatter.hms(-.infinity), "0:00:00")
        XCTAssertEqual(DurationFormatter.hms(1e19), "9999:59:59")
        XCTAssertEqual(DurationFormatter.hms(.infinity), "9999:59:59")
        XCTAssertEqual(DurationFormatter.hms(.greatestFiniteMagnitude), "9999:59:59")
    }

    func testMSHandlesExtremeValues() {
        XCTAssertEqual(DurationFormatter.ms(-1), "00:00")
        XCTAssertEqual(DurationFormatter.ms(.nan), "00:00")
        XCTAssertEqual(DurationFormatter.ms(1e19), "599999:59")
        XCTAssertEqual(DurationFormatter.ms(.infinity), "599999:59")
    }

    func testSignedMSHandlesExtremeValues() {
        XCTAssertEqual(DurationFormatter.signedMs(.nan), "+0:00")
        XCTAssertEqual(DurationFormatter.signedMs(1e19), "+599999:59")
        XCTAssertEqual(DurationFormatter.signedMs(-1e19), "-599999:59")
        XCTAssertEqual(DurationFormatter.signedMs(-.infinity), "-599999:59")
    }

    func testPaceHandlesExtremeValues() {
        XCTAssertEqual(DurationFormatter.pace(.nan), "—")
        XCTAssertEqual(DurationFormatter.pace(.infinity), "—")
        XCTAssertEqual(DurationFormatter.pace(-1e19), "—")
        XCTAssertEqual(DurationFormatter.pace(1e19), "599999'59\" /km")
    }

    func testSafeIntClampsInsteadOfTrapping() {
        XCTAssertEqual(DurationFormatter.safeInt(.nan), 0)
        XCTAssertEqual(DurationFormatter.safeInt(.infinity), Int.max)
        XCTAssertEqual(DurationFormatter.safeInt(-.infinity), 0)
        XCTAssertEqual(DurationFormatter.safeInt(1e19), Int.max)
        XCTAssertEqual(DurationFormatter.safeInt(-1e19), 0)
        XCTAssertEqual(DurationFormatter.safeInt(-5, lowerBound: Int.min), -5)
        XCTAssertEqual(DurationFormatter.safeInt(1234.9), 1234)
        XCTAssertEqual(DurationFormatter.safeInt(9_999, upperBound: 100), 100)
    }
}
