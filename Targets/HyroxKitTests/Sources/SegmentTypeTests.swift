//
//  SegmentTypeTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class SegmentTypeTests: XCTestCase {

    func testRunTracksLocation() {
        XCTAssertTrue(SegmentType.run.tracksLocation)
    }

    func testRoxZoneTracksLocation() {
        XCTAssertTrue(SegmentType.roxZone.tracksLocation)
    }

    func testStationDoesNotTrackLocation() {
        XCTAssertFalse(SegmentType.station.tracksLocation)
    }

    func testAllTypesTrackHeartRate() {
        for type in [SegmentType.run, .roxZone, .station] {
            XCTAssertTrue(type.tracksHeartRate, "\(type) should track heart rate")
        }
    }
}
