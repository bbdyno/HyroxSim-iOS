//
//  StationTargetTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

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

    /// 손상된 템플릿(무한대·NaN·Int 범위 초과)을 표시해도 트랩하지 않는다 (P0 크래시 회귀 방지)
    func testExtremeTargetsDoNotTrap() {
        XCTAssertEqual(StationTarget.distance(meters: .nan).formatted, "0 m")
        XCTAssertEqual(StationTarget.distance(meters: -1).formatted, "0 m")
        XCTAssertFalse(StationTarget.distance(meters: 1e19).formatted.isEmpty)
        XCTAssertFalse(StationTarget.duration(seconds: .infinity).formatted.isEmpty)
        XCTAssertEqual(StationTarget.duration(seconds: .nan).formatted, "00:00")
    }
}
