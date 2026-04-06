//
//  HistoryViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxKit
@testable import HyroxSim

@MainActor
final class HistoryViewModelTests: XCTestCase {

    private func makePersistence() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    private func makeWorkout(finishedAtOffset: TimeInterval) -> CompletedWorkout {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return CompletedWorkout(
            templateName: "Test",
            startedAt: start,
            finishedAt: start.addingTimeInterval(finishedAtOffset),
            segments: []
        )
    }

    func testEmptyState() throws {
        let vm = HistoryViewModel(persistence: try makePersistence())
        vm.load()
        XCTAssertTrue(vm.workouts.isEmpty)
    }

    func testLoadMultipleWorkoutsSorted() throws {
        let persistence = try makePersistence()
        let w1 = makeWorkout(finishedAtOffset: 100)
        let w2 = makeWorkout(finishedAtOffset: 300)
        let w3 = makeWorkout(finishedAtOffset: 200)

        try persistence.saveCompletedWorkout(w1)
        try persistence.saveCompletedWorkout(w2)
        try persistence.saveCompletedWorkout(w3)

        let vm = HistoryViewModel(persistence: persistence)
        vm.load()

        XCTAssertEqual(vm.workouts.count, 3)
        // Most recent first
        XCTAssertEqual(vm.workouts[0].id, w2.id)
        XCTAssertEqual(vm.workouts[1].id, w3.id)
        XCTAssertEqual(vm.workouts[2].id, w1.id)
    }

    func testDeleteWorkout() throws {
        let persistence = try makePersistence()
        let w1 = makeWorkout(finishedAtOffset: 100)
        let w2 = makeWorkout(finishedAtOffset: 200)

        try persistence.saveCompletedWorkout(w1)
        try persistence.saveCompletedWorkout(w2)

        let vm = HistoryViewModel(persistence: persistence)
        vm.load()
        XCTAssertEqual(vm.workouts.count, 2)

        vm.delete(at: 0)
        XCTAssertEqual(vm.workouts.count, 1)
    }
}
