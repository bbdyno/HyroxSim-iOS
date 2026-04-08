//
//  PersistenceControllerTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxKit

@MainActor
final class PersistenceControllerTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    private func makeController() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    private func makeSampleWorkout(
        finishedAtOffset: TimeInterval = 600,
        division: HyroxDivision? = .menOpenSingle
    ) -> CompletedWorkout {
        let start = t0
        let finish = t0.addingTimeInterval(finishedAtOffset)
        let segments = [
            SegmentRecord(
                segmentId: UUID(),
                index: 0,
                type: .run,
                startedAt: start,
                endedAt: start.addingTimeInterval(300),
                measurements: SegmentMeasurements(
                    locationSamples: [
                        LocationSample(timestamp: start, latitude: 37.5665, longitude: 126.978, horizontalAccuracy: 5)
                    ],
                    heartRateSamples: [
                        HeartRateSample(timestamp: start.addingTimeInterval(10), bpm: 150)
                    ]
                ),
                plannedDistanceMeters: 1000
            ),
            SegmentRecord(
                segmentId: UUID(),
                index: 1,
                type: .station,
                startedAt: start.addingTimeInterval(300),
                endedAt: finish,
                stationDisplayName: "SkiErg"
            )
        ]
        return CompletedWorkout(
            templateName: "Test Workout",
            division: division,
            startedAt: start,
            finishedAt: finish,
            segments: segments
        )
    }

    // MARK: - Save & Fetch

    func testSaveAndFetchCompletedWorkout() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        let fetched = try ctrl.fetchAllCompletedWorkouts()

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, workout.id)
        XCTAssertEqual(fetched[0].templateName, "Test Workout")
    }

    // MARK: - Segments Cascade

    func testSegmentsPreservedOnFetch() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        let fetched = try ctrl.fetchCompletedWorkout(id: workout.id)

        XCTAssertEqual(fetched.segments.count, 2)
        XCTAssertEqual(fetched.segments[0].type, .run)
        XCTAssertEqual(fetched.segments[1].type, .station)
        XCTAssertEqual(fetched.segments[0].duration, 300, accuracy: 0.001)
        XCTAssertEqual(fetched.segments[0].plannedDistanceMeters, 1000)
        XCTAssertEqual(fetched.segments[1].stationDisplayName, "SkiErg")
    }

    // MARK: - Measurements Round-trip

    func testMeasurementsRoundTrip() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        let fetched = try ctrl.fetchCompletedWorkout(id: workout.id)

        let runSegment = fetched.segments[0]
        XCTAssertEqual(runSegment.measurements.locationSamples.count, 1)
        XCTAssertEqual(runSegment.measurements.heartRateSamples.count, 1)
        XCTAssertEqual(runSegment.measurements.heartRateSamples[0].bpm, 150)
    }

    // MARK: - Delete

    func testDeleteCompletedWorkout() throws {
        let ctrl = try makeController()
        let workout = makeSampleWorkout()

        try ctrl.saveCompletedWorkout(workout)
        try ctrl.deleteCompletedWorkout(id: workout.id)

        let fetched = try ctrl.fetchAllCompletedWorkouts()
        XCTAssertEqual(fetched.count, 0)
    }

    // MARK: - Not Found

    func testFetchNotFoundThrows() throws {
        let ctrl = try makeController()
        let randomId = UUID()

        XCTAssertThrowsError(try ctrl.fetchCompletedWorkout(id: randomId)) { error in
            XCTAssertEqual(error as? PersistenceError, .notFound(id: randomId))
        }
    }

    // MARK: - Sort Order

    func testFetchAllSortedByMostRecent() throws {
        let ctrl = try makeController()

        let w1 = makeSampleWorkout(finishedAtOffset: 100)
        let w2 = makeSampleWorkout(finishedAtOffset: 300)
        let w3 = makeSampleWorkout(finishedAtOffset: 200)

        try ctrl.saveCompletedWorkout(w1)
        try ctrl.saveCompletedWorkout(w2)
        try ctrl.saveCompletedWorkout(w3)

        let fetched = try ctrl.fetchAllCompletedWorkouts()
        XCTAssertEqual(fetched.count, 3)
        // Most recent first
        XCTAssertEqual(fetched[0].id, w2.id)
        XCTAssertEqual(fetched[1].id, w3.id)
        XCTAssertEqual(fetched[2].id, w1.id)
    }
}
