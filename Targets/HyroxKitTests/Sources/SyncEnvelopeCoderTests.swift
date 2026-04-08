//
//  SyncEnvelopeCoderTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class SyncEnvelopeCoderTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    func testTemplateRoundTrip() throws {
        let template = WorkoutTemplate(
            name: "Custom", segments: [.run(), .station(.skiErg)]
        )
        let envelope = try SyncEnvelopeCoder.encode(template, kind: .template)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        let restored = try SyncEnvelopeCoder.fromDictionary(dict)
        let decoded = try SyncEnvelopeCoder.decodeTemplate(restored)

        XCTAssertEqual(decoded.id, template.id)
        XCTAssertEqual(decoded.name, "Custom")
        XCTAssertEqual(decoded.segments.count, 2)
    }

    func testCompletedWorkoutRoundTrip() throws {
        let workout = CompletedWorkout(
            templateName: "Test",
            division: .menOpenSingle,
            startedAt: t0,
            finishedAt: t0.addingTimeInterval(600),
            segments: [
                SegmentRecord(
                    segmentId: UUID(), index: 0, type: .run,
                    startedAt: t0, endedAt: t0.addingTimeInterval(300),
                    measurements: SegmentMeasurements(heartRateSamples: [
                        HeartRateSample(timestamp: t0.addingTimeInterval(10), bpm: 155)
                    ])
                )
            ]
        )
        let envelope = try SyncEnvelopeCoder.encode(workout, kind: .completedWorkout)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        let restored = try SyncEnvelopeCoder.fromDictionary(dict)
        let decoded = try SyncEnvelopeCoder.decodeCompletedWorkout(restored)

        XCTAssertEqual(decoded.id, workout.id)
        XCTAssertEqual(decoded.segments.count, 1)
        XCTAssertEqual(decoded.segments[0].measurements.heartRateSamples[0].bpm, 155)
    }

    func testDeletedIdRoundTrip() throws {
        let id = UUID()
        let envelope = try SyncEnvelopeCoder.encode(id, kind: .templateDeleted)
        let dict = try SyncEnvelopeCoder.toDictionary(envelope)
        let restored = try SyncEnvelopeCoder.fromDictionary(dict)
        let decoded = try SyncEnvelopeCoder.decodeDeletedId(restored)

        XCTAssertEqual(decoded, id)
    }

    func testInvalidDictThrows() {
        let badDict: [String: Any] = ["wrong": "data"]
        XCTAssertThrowsError(try SyncEnvelopeCoder.fromDictionary(badDict)) { error in
            XCTAssertEqual(error as? SyncError, .decodingFailed)
        }
    }
}
