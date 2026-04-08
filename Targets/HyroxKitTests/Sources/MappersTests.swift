//
//  MappersTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxKit

final class MappersTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    // MARK: - CompletedWorkoutMapper

    func testCompletedWorkoutRoundTrip() throws {
        let original = CompletedWorkout(
            templateName: "Men's Open — Singles",
            division: .menOpenSingle,
            startedAt: t0,
            finishedAt: t0.addingTimeInterval(3600),
            segments: [
                SegmentRecord(
                    segmentId: UUID(),
                    index: 0,
                    type: .run,
                    startedAt: t0,
                    endedAt: t0.addingTimeInterval(300),
                    pausedDuration: 10,
                    measurements: SegmentMeasurements(
                        locationSamples: [
                            LocationSample(timestamp: t0, latitude: 37.5, longitude: 127.0, horizontalAccuracy: 5)
                        ],
                        heartRateSamples: [
                            HeartRateSample(timestamp: t0.addingTimeInterval(10), bpm: 155)
                        ]
                    ),
                    plannedDistanceMeters: 1000
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 1,
                    type: .roxZone,
                    startedAt: t0.addingTimeInterval(300),
                    endedAt: t0.addingTimeInterval(330)
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 2,
                    type: .station,
                    startedAt: t0.addingTimeInterval(330),
                    endedAt: t0.addingTimeInterval(600),
                    stationDisplayName: "SkiErg"
                )
            ]
        )

        let stored = try CompletedWorkoutMapper.toStored(original)
        let restored = try CompletedWorkoutMapper.toDomain(stored)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.templateName, original.templateName)
        XCTAssertEqual(restored.division, original.division)
        XCTAssertEqual(restored.segments.count, 3)
        XCTAssertEqual(restored.segments[0].type, .run)
        XCTAssertEqual(restored.segments[0].pausedDuration, 10, accuracy: 0.001)
        XCTAssertEqual(restored.segments[0].measurements.locationSamples.count, 1)
        XCTAssertEqual(restored.segments[0].measurements.heartRateSamples[0].bpm, 155)
        XCTAssertEqual(restored.segments[0].plannedDistanceMeters, 1000)
        XCTAssertEqual(restored.segments[1].type, .roxZone)
        XCTAssertEqual(restored.segments[2].type, .station)
        XCTAssertEqual(restored.segments[2].stationDisplayName, "SkiErg")
    }

    func testEmptySegmentsWorkoutRoundTrip() throws {
        let original = CompletedWorkout(
            templateName: "Empty",
            startedAt: t0,
            finishedAt: t0,
            segments: []
        )

        let stored = try CompletedWorkoutMapper.toStored(original)
        let restored = try CompletedWorkoutMapper.toDomain(stored)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.segments.count, 0)
    }

    // MARK: - WorkoutTemplateMapper

    func testWorkoutTemplateRoundTrip() throws {
        let original = WorkoutTemplate(
            name: "Custom Half",
            segments: [
                .run(distanceMeters: 500),
                .roxZone(),
                .station(.wallBalls, target: .reps(count: 50), weightKg: 6)
            ]
        )

        let stored = try WorkoutTemplateMapper.toStored(original)
        let restored = try WorkoutTemplateMapper.toDomain(stored)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.name, "Custom Half")
        XCTAssertEqual(restored.segments.count, 3)
        XCTAssertEqual(restored.segments[0].distanceMeters, 500)
        XCTAssertEqual(restored.segments[2].stationKind, .wallBalls)
        XCTAssertEqual(restored.segments[2].weightKg, 6)
        XCTAssertFalse(restored.isBuiltIn)
    }
}
