//
//  HeartRateSampleTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxKit

final class HeartRateSampleTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let sample = HeartRateSample(
            timestamp: Date(timeIntervalSinceReferenceDate: 200),
            bpm: 155
        )

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(HeartRateSample.self, from: data)

        XCTAssertEqual(decoded, sample)
        XCTAssertEqual(decoded.bpm, 155)
    }
}
