//
//  ActiveWorkoutViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxKit
@testable import HyroxSim

@MainActor
final class ActiveWorkoutViewModelTests: XCTestCase {

    private func makeVM(
        segments: [WorkoutSegment] = [.run(), .roxZone(), .station(.skiErg, target: .distance(meters: 1000))]
    ) throws -> ActiveWorkoutViewModel {
        let template = WorkoutTemplate(name: "Test", segments: segments)
        let persistence = try PersistenceController(inMemory: true)
        return ActiveWorkoutViewModel(
            template: template,
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200
        )
    }

    // MARK: - Start

    func testStartSetsSegmentLabel() async throws {
        let vm = try makeVM()
        await vm.start()
        XCTAssertEqual(vm.segmentLabel, "RUN 1 / 1")
        XCTAssertEqual(vm.accentKind, .run)
        vm.cancelWorkout()
    }

    // MARK: - Advance

    func testAdvanceToRoxZone() async throws {
        let vm = try makeVM()
        await vm.start()
        vm.advance()
        XCTAssertEqual(vm.segmentLabel, "ROX ZONE")
        XCTAssertEqual(vm.accentKind, .roxZone)
        XCTAssertEqual(vm.segmentSubLabel, "→ SkiErg")
        vm.cancelWorkout()
    }

    func testAdvanceToStation() async throws {
        let vm = try makeVM()
        await vm.start()
        vm.advance() // → roxZone
        vm.advance() // → station
        XCTAssertEqual(vm.segmentLabel, "STATION 1 / 1")
        XCTAssertEqual(vm.accentKind, .station)
        XCTAssertEqual(vm.stationNameText, "SkiErg")
        XCTAssertEqual(vm.stationTargetText, "1000 m")
        XCTAssertEqual(vm.paceText, "—")
        XCTAssertEqual(vm.distanceText, "—")
        vm.cancelWorkout()
    }

    // MARK: - Finish

    func testFinishSavesToPersistence() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let template = WorkoutTemplate(name: "Test", segments: [.run()])
        let vm = ActiveWorkoutViewModel(
            template: template,
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200
        )

        let expectation = XCTestExpectation(description: "finish called")
        vm.finishHandler = { (_: CompletedWorkout) in expectation.fulfill() }

        await vm.start()
        vm.advance() // finishes (only 1 segment)
        await fulfillment(of: [expectation], timeout: 2)

        let workouts = try persistence.fetchAllCompletedWorkouts()
        XCTAssertEqual(workouts.count, 1)
    }

    // MARK: - Undo

    func testUndo() async throws {
        let vm = try makeVM()
        await vm.start()
        vm.advance() // → roxZone
        vm.undo()    // → back to run
        XCTAssertEqual(vm.segmentLabel, "RUN 1 / 1")
        vm.cancelWorkout()
    }

    // MARK: - Pause / Resume

    func testTogglePause() async throws {
        let vm = try makeVM()
        await vm.start()
        XCTAssertFalse(vm.isPaused)

        vm.togglePause()
        XCTAssertTrue(vm.isPaused)

        vm.togglePause()
        XCTAssertFalse(vm.isPaused)
        vm.cancelWorkout()
    }

    // MARK: - End Workout

    func testEndWorkoutSaves() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let template = WorkoutTemplate(name: "Test", segments: [.run(), .station(.skiErg)])
        let vm = ActiveWorkoutViewModel(
            template: template,
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200
        )

        let expectation = XCTestExpectation(description: "finish called")
        vm.finishHandler = { (_: CompletedWorkout) in expectation.fulfill() }

        await vm.start()
        vm.endWorkout()
        await fulfillment(of: [expectation], timeout: 2)

        let workouts = try persistence.fetchAllCompletedWorkouts()
        XCTAssertEqual(workouts.count, 1)
    }
}
