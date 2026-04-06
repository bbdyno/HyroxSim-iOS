//
//  DistanceFormatterTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxKit

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
}
