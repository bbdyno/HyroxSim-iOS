//
//  WorkoutTemplateTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxKit

final class WorkoutTemplateTests: XCTestCase {

    func testEmptySegmentsValidationFails() {
        let template = WorkoutTemplate(name: "Empty", segments: [])
        XCTAssertThrowsError(try template.validate()) { error in
            XCTAssertEqual(error as? WorkoutTemplate.ValidationError, .emptySegments)
        }
    }

    func testValidTemplateDoesNotThrow() {
        let template = WorkoutTemplate(
            name: "Test",
            segments: [.run(), .roxZone(), .station(.skiErg)]
        )
        XCTAssertNoThrow(try template.validate())
    }

    func testTotalRunDistance() {
        let template = WorkoutTemplate(
            name: "Test",
            segments: [
                .run(distanceMeters: 1000),
                .roxZone(),
                .station(.skiErg),
                .run(distanceMeters: 1000),
                .roxZone(),
                .station(.rowing)
            ]
        )
        XCTAssertEqual(template.totalRunDistanceMeters, 2000)
    }

    func testStationCount() {
        let template = WorkoutTemplate(
            name: "Test",
            segments: [
                .run(), .roxZone(), .station(.skiErg),
                .run(), .roxZone(), .station(.rowing)
            ]
        )
        XCTAssertEqual(template.stationCount, 2)
    }

    func testEstimatedDurationIsPositive() {
        let template = WorkoutTemplate(
            name: "Test",
            segments: [.run(), .roxZone(), .station(.skiErg)]
        )
        XCTAssertGreaterThan(template.estimatedDurationSeconds, 0)
    }

    func testValidateDetectsInvalidSegment() {
        let badSegment = WorkoutSegment(type: .run, weightKg: 10)
        let template = WorkoutTemplate(name: "Bad", segments: [badSegment])
        XCTAssertThrowsError(try template.validate())
    }
}
