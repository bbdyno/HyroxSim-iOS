//
//  HeartRateZoneTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class HeartRateZoneTests: XCTestCase {

    // MARK: - Zone Calculation

    func testBpm120Max200IsZ2() {
        // 120/200 = 60% → Z2 boundary
        let zone = HeartRateZone.zone(forHeartRate: 120, maxHeartRate: 200)
        XCTAssertEqual(zone, .z2)
    }

    func testBpm170Max200IsZ4() {
        // 170/200 = 85% → Z4
        let zone = HeartRateZone.zone(forHeartRate: 170, maxHeartRate: 200)
        XCTAssertEqual(zone, .z4)
    }

    func testBpm200Max200IsZ5() {
        // 200/200 = 100% → Z5
        let zone = HeartRateZone.zone(forHeartRate: 200, maxHeartRate: 200)
        XCTAssertEqual(zone, .z5)
    }

    func testBpm50Max200ClampsToZ1() {
        // 50/200 = 25% → clamped to Z1
        let zone = HeartRateZone.zone(forHeartRate: 50, maxHeartRate: 200)
        XCTAssertEqual(zone, .z1)
    }

    func testAbove100PercentClampsToZ5() {
        let zone = HeartRateZone.zone(forHeartRate: 220, maxHeartRate: 200)
        XCTAssertEqual(zone, .z5)
    }

    func testBpm100Max200IsZ1() {
        // 100/200 = 50% → Z1 (50-60% range)
        let zone = HeartRateZone.zone(forHeartRate: 100, maxHeartRate: 200)
        XCTAssertEqual(zone, .z1)
    }

    func testBpm150Max200IsZ3() {
        // 150/200 = 75% → Z3
        let zone = HeartRateZone.zone(forHeartRate: 150, maxHeartRate: 200)
        XCTAssertEqual(zone, .z3)
    }

    // MARK: - Labels & Descriptions

    func testZoneLabels() {
        XCTAssertEqual(HeartRateZone.z1.label, "Z1")
        XCTAssertEqual(HeartRateZone.z5.label, "Z5")
    }

    func testZoneDescriptions() {
        XCTAssertEqual(HeartRateZone.z1.description, "Very Light")
        XCTAssertEqual(HeartRateZone.z3.description, "Moderate")
        XCTAssertEqual(HeartRateZone.z5.description, "Maximum")
    }

    func testZoneRanges() {
        XCTAssertEqual(HeartRateZone.z1.range, 0.50...0.60)
        XCTAssertEqual(HeartRateZone.z5.range, 0.90...1.00)
    }
}
