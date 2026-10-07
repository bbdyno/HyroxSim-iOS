//
//  DistanceFormatterTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class DistanceFormatterTests: XCTestCase {

    func testKilometers() {
        XCTAssertEqual(DistanceFormatter.short(1234), "1.23 km")
        XCTAssertEqual(DistanceFormatter.short(1000), "1.00 km")
        XCTAssertEqual(DistanceFormatter.short(10500), "10.50 km")
    }

    func testMeters() {
        XCTAssertEqual(DistanceFormatter.short(240), "240 m")
        XCTAssertEqual(DistanceFormatter.short(0), "0 m")
        XCTAssertEqual(DistanceFormatter.short(999), "999 m")
    }

    /// 비정상 값이 들어와도 트랩하지 않는다 (P0 크래시 회귀 방지)
    func testExtremeValuesDoNotTrap() {
        XCTAssertEqual(DistanceFormatter.short(.nan), "0 m")
        XCTAssertEqual(DistanceFormatter.short(.infinity), "0 m")
        XCTAssertEqual(DistanceFormatter.short(-.infinity), "0 m")
        XCTAssertEqual(DistanceFormatter.short(-50), "-50 m")
        XCTAssertFalse(DistanceFormatter.short(1e19).isEmpty)
    }
}
