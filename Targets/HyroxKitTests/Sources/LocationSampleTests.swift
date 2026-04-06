//
//  LocationSampleTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxKit

final class LocationSampleTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let sample = LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 100),
            latitude: 37.5665,
            longitude: 126.9780,
            altitude: 38.0,
            horizontalAccuracy: 5.0,
            speed: 3.5,
            course: 90.0
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(LocationSample.self, from: data)

        XCTAssertEqual(decoded, sample)
        XCTAssertEqual(decoded.latitude, 37.5665)
        XCTAssertEqual(decoded.speed, 3.5)
    }

    func testOptionalFieldsNil() throws {
        let sample = LocationSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 0),
            latitude: 0,
            longitude: 0,
            horizontalAccuracy: 10.0
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(LocationSample.self, from: data)

        XCTAssertNil(decoded.altitude)
        XCTAssertNil(decoded.speed)
        XCTAssertNil(decoded.course)
    }
}
