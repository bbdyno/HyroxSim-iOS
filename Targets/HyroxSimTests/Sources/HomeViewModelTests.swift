import XCTest
import HyroxKit
@testable import HyroxSim

@MainActor
final class HomeViewModelTests: XCTestCase {

    private func makePersistence() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    func testLoadPresetsCount() throws {
        let vm = HomeViewModel(persistence: try makePersistence())
        vm.load()
        XCTAssertEqual(vm.presets.count, 9)
    }

    func testEmptyRecentWorkouts() throws {
        let vm = HomeViewModel(persistence: try makePersistence())
        vm.load()
        XCTAssertTrue(vm.recentWorkouts.isEmpty)
        XCTAssertNil(vm.mostRecentWorkout)
    }

    func testRecentWorkoutAfterSave() throws {
        let persistence = try makePersistence()
        let workout = CompletedWorkout(
            templateName: "Test",
            startedAt: Date(),
            finishedAt: Date().addingTimeInterval(600),
            segments: []
        )
        try persistence.saveCompletedWorkout(workout)

        let vm = HomeViewModel(persistence: persistence)
        vm.load()
        XCTAssertEqual(vm.recentWorkouts.count, 1)
        XCTAssertNotNil(vm.mostRecentWorkout)
        XCTAssertEqual(vm.mostRecentWorkout?.id, workout.id)
    }
}
