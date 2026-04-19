//
//  GarminImportServiceTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/19/26.
//

import XCTest
import HyroxCore
import HyroxPersistenceApple
@testable import HyroxSim

final class GarminImportServiceTests: XCTestCase {

    func test_handleWorkoutCompleted_persistsWorkout() throws {
        let persistence = try PersistenceController(inMemory: true)
        let service = GarminImportService(makePersistence: { persistence })

        let envelope: [String: Any] = [
            GarminMessageCodec.Key.version: 1,
            GarminMessageCodec.Key.type: GarminMessageCodec.MessageType.workoutCompleted,
            GarminMessageCodec.Key.id: "wk-42",
            GarminMessageCodec.Key.payload: [
                "id": UUID().uuidString,
                "templateName": "Hyrox Men's Open",
                "division": "menOpenSingle",
                "startedAtMs": 1_000,
                "finishedAtMs": 10_000,
                "source": "garmin",
                "segments": [
                    [
                        "index": 0,
                        "type": "run",
                        "startedAtMs": 1_000,
                        "endedAtMs": 2_000,
                        "pausedDurationMs": 0,
                    ],
                ],
            ],
        ]

        service.handle(envelope: envelope)

        let all = try persistence.fetchAllCompletedWorkouts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.templateName, "Hyrox Men's Open")
        XCTAssertEqual(all.first?.segments.count, 1)
    }

    func test_handleNonWorkoutEnvelope_doesNothing() throws {
        let persistence = try PersistenceController(inMemory: true)
        let service = GarminImportService(makePersistence: { persistence })

        service.handle(envelope: [
            GarminMessageCodec.Key.type: "hello",
            GarminMessageCodec.Key.id: "x",
        ])

        let all = try persistence.fetchAllCompletedWorkouts()
        XCTAssertTrue(all.isEmpty)
    }

    func test_goalSync_returnsNotPaired_whenBridgeNotPaired() {
        // In the test target, ConnectIQ.xcframework may not be linked; the
        // stub bridge reports isPaired=false.
        let svc = GarminGoalSyncService()
        let result = svc.sendGoal(
            division: .menOpenSingle,
            templateName: "Preset",
            targetTotalMs: 90 * 60 * 1000,
            targetSegmentsMs: Array(repeating: Int64(150_000), count: 31)
        )
        // When ConnectIQ is linked in Debug but unpaired at runtime, this is
        // still .notPaired — so the assertion holds in both builds.
        XCTAssertEqual(result, .notPaired)
    }
}
