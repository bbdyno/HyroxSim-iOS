//
//  WorkoutTemplateTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

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

    func testLogicalSegmentsExcludeRoxZone() {
        let template = WorkoutTemplate(
            name: "Test",
            segments: [.run(), .roxZone(), .station(.skiErg)]
        )

        XCTAssertEqual(template.logicalSegments.map(\.type), [.run, .station])
    }

    func testMaterializedSegmentsInsertRoxBetweenRunAndStationBoundaries() {
        let segments: [WorkoutSegment] = [
            .run(distanceMeters: 1000),
            .station(.skiErg),
            .run(distanceMeters: 1000)
        ]

        let materialized = WorkoutTemplate.materializedSegments(from: segments, usesRoxZone: true)

        XCTAssertEqual(
            materialized.map(\.type),
            [.run, .roxZone, .station, .roxZone, .run]
        )
    }

    func testMaterializedSegmentsSkipRoxWhenDisabled() {
        let segments: [WorkoutSegment] = [
            .run(distanceMeters: 1000),
            .station(.skiErg),
            .run(distanceMeters: 1000)
        ]

        let materialized = WorkoutTemplate.materializedSegments(from: segments, usesRoxZone: false)

        XCTAssertEqual(materialized.map(\.type), [.run, .station, .run])
    }

    func testSettingUsesRoxZonePreservesExistingRoxSegmentsWhenEnabled() {
        var rox = WorkoutSegment.roxZone()
        rox.goalDurationSeconds = 91
        let template = WorkoutTemplate(
            name: "Test",
            segments: [.run(distanceMeters: 1000), rox, .station(.skiErg)],
            usesRoxZone: true
        )

        let updated = template.settingUsesRoxZone(true)

        XCTAssertEqual(updated.segments.count, 3)
        XCTAssertEqual(updated.segments[1].type, .roxZone)
        XCTAssertEqual(updated.segments[1].goalDurationSeconds, 91)
    }
}
