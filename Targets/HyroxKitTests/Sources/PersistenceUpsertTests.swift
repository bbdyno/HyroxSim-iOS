import XCTest
@testable import HyroxKit

@MainActor
final class PersistenceUpsertTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    private func makeController() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    // MARK: - CompletedWorkout Upsert

    func testUpsertNewWorkout() throws {
        let ctrl = try makeController()
        let workout = CompletedWorkout(
            templateName: "Test", startedAt: t0, finishedAt: t0.addingTimeInterval(600), segments: []
        )
        try ctrl.upsertCompletedWorkout(workout)
        let all = try ctrl.fetchAllCompletedWorkouts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, workout.id)
    }

    func testUpsertOverwritesExisting() throws {
        let ctrl = try makeController()
        let id = UUID()
        let w1 = CompletedWorkout(
            id: id, templateName: "V1", startedAt: t0, finishedAt: t0.addingTimeInterval(300), segments: []
        )
        let w2 = CompletedWorkout(
            id: id, templateName: "V2", startedAt: t0, finishedAt: t0.addingTimeInterval(600), segments: []
        )
        try ctrl.upsertCompletedWorkout(w1)
        try ctrl.upsertCompletedWorkout(w2)

        let all = try ctrl.fetchAllCompletedWorkouts()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].templateName, "V2")
    }

    // MARK: - Template Upsert

    func testUpsertNewTemplate() throws {
        let ctrl = try makeController()
        let template = WorkoutTemplate(name: "Custom", segments: [.run()])
        try ctrl.upsertTemplate(template)
        let all = try ctrl.fetchAllTemplates()
        XCTAssertEqual(all.count, 1)
    }

    func testUpsertOverwritesTemplate() throws {
        let ctrl = try makeController()
        let id = UUID()
        let t1 = WorkoutTemplate(id: id, name: "V1", segments: [.run()])
        let t2 = WorkoutTemplate(id: id, name: "V2", segments: [.run(), .station(.skiErg)])

        try ctrl.upsertTemplate(t1)
        try ctrl.upsertTemplate(t2)

        let all = try ctrl.fetchAllTemplates()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].name, "V2")
        XCTAssertEqual(all[0].segments.count, 2)
    }
}
