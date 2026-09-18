//
//  PersistenceUpsertTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore
import HyroxPersistenceApple

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

    // MARK: - Deleted Workouts (tombstones)

    private func makeWorkout(id: UUID = UUID(), name: String = "Test") -> CompletedWorkout {
        CompletedWorkout(
            id: id, templateName: name, startedAt: t0, finishedAt: t0.addingTimeInterval(600), segments: []
        )
    }

    /// The counterpart re-sends its whole history on every activation, which used
    /// to resurrect a record the user had deleted.
    func testDeletedWorkoutIsNotResurrectedByUpsert() throws {
        let ctrl = try makeController()
        let workout = makeWorkout()

        try ctrl.saveCompletedWorkout(workout)
        try ctrl.deleteCompletedWorkout(id: workout.id)

        XCTAssertFalse(try ctrl.upsertCompletedWorkout(workout), "upsert must refuse a deleted record")
        XCTAssertEqual(try ctrl.fetchAllCompletedWorkouts().count, 0)

        // Still refused after the counterpart retries.
        XCTAssertFalse(try ctrl.upsertCompletedWorkout(workout))
        XCTAssertEqual(try ctrl.fetchAllCompletedWorkouts().count, 0)
    }

    func testDeleteRecordsTombstoneAndPostsNotification() throws {
        let ctrl = try makeController()
        let workout = makeWorkout()
        try ctrl.saveCompletedWorkout(workout)

        expectation(forNotification: .hyroxCompletedWorkoutDeleted, object: nil) { note in
            (note.userInfo?[PersistenceController.deletedWorkoutIdKey] as? UUID) == workout.id
        }
        try ctrl.deleteCompletedWorkout(id: workout.id)
        waitForExpectations(timeout: 1)

        XCTAssertTrue(ctrl.isCompletedWorkoutDeleted(id: workout.id))
        XCTAssertEqual(ctrl.deletedCompletedWorkoutIds(), [workout.id])
    }

    /// A deletion arriving from the counterpart removes the local copy and
    /// tombstones the ID, but must not post the outbound notification (that would
    /// bounce the deletion straight back to the sender).
    func testRemoteDeletionRemovesRecordWithoutReBroadcasting() throws {
        let ctrl = try makeController()
        let workout = makeWorkout()
        try ctrl.saveCompletedWorkout(workout)

        let noBroadcast = expectation(forNotification: .hyroxCompletedWorkoutDeleted, object: nil)
        noBroadcast.isInverted = true

        XCTAssertTrue(try ctrl.applyRemoteCompletedWorkoutDeletion(id: workout.id))
        wait(for: [noBroadcast], timeout: 0.2)
        XCTAssertEqual(try ctrl.fetchAllCompletedWorkouts().count, 0)
        XCTAssertFalse(try ctrl.upsertCompletedWorkout(workout))

        // Unknown ID: nothing to remove locally, but the tombstone is still recorded
        // so the record can't arrive later.
        let unseen = makeWorkout()
        XCTAssertFalse(try ctrl.applyRemoteCompletedWorkoutDeletion(id: unseen.id))
        XCTAssertTrue(ctrl.isCompletedWorkoutDeleted(id: unseen.id))
        XCTAssertFalse(try ctrl.upsertCompletedWorkout(unseen))
    }

    func testTombstoneIsIdempotentAndScopedToItsId() throws {
        let ctrl = try makeController()
        let deleted = makeWorkout()
        let kept = makeWorkout(name: "Kept")

        XCTAssertTrue(try ctrl.markCompletedWorkoutDeleted(id: deleted.id))
        XCTAssertFalse(try ctrl.markCompletedWorkoutDeleted(id: deleted.id), "second mark is a no-op")
        XCTAssertEqual(ctrl.deletedCompletedWorkoutIds(), [deleted.id])

        XCTAssertTrue(try ctrl.upsertCompletedWorkout(kept))
        XCTAssertEqual(try ctrl.fetchAllCompletedWorkouts().map(\.id), [kept.id])
    }

    func testPruneTombstonesDropsOnlyOlderEntries() throws {
        let ctrl = try makeController()
        let old = UUID()
        let recent = UUID()
        try ctrl.markCompletedWorkoutDeleted(id: old, at: t0)
        try ctrl.markCompletedWorkoutDeleted(id: recent, at: t0.addingTimeInterval(3600))

        XCTAssertEqual(try ctrl.pruneCompletedWorkoutTombstones(before: t0.addingTimeInterval(60)), 1)
        XCTAssertFalse(ctrl.isCompletedWorkoutDeleted(id: old))
        XCTAssertTrue(ctrl.isCompletedWorkoutDeleted(id: recent))
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

    // MARK: - RaceTarget Upsert

    private func makeRaceTarget(id: UUID = UUID(), eventName: String = "HYROX Seoul") -> RaceTarget {
        RaceTarget(
            id: id,
            eventName: eventName,
            city: "Seoul",
            date: t0.addingTimeInterval(30 * 86_400),
            division: .menOpenSingle,
            goalDurationSeconds: 5_400,
            createdAt: t0,
            updatedAt: t0
        )
    }

    /// 같은 목표가 두 번 도착해도(사용자 저장 + 동기화 에코) 한 줄만 남아야 한다.
    func testUpsertRaceTargetIsIdempotent() throws {
        let ctrl = try makeController()
        let target = makeRaceTarget()

        try ctrl.upsertRaceTarget(target)
        try ctrl.upsertRaceTarget(target)

        let all = try ctrl.fetchRaceTargets()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, target.id)
    }

    func testUpsertRaceTargetOverwritesExisting() throws {
        let ctrl = try makeController()
        let id = UUID()
        var edited = makeRaceTarget(id: id)
        try ctrl.upsertRaceTarget(makeRaceTarget(id: id))

        edited.eventName = "HYROX Seoul Major"
        edited.goalDurationSeconds = 4_800
        edited.updatedAt = t0.addingTimeInterval(3_600)
        try ctrl.upsertRaceTarget(edited)

        let all = try ctrl.fetchRaceTargets()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].eventName, "HYROX Seoul Major")
        XCTAssertEqual(all[0].goalDurationSeconds, 4_800)
        XCTAssertEqual(all[0].updatedAt, t0.addingTimeInterval(3_600))
    }

    /// 목표를 지우면 다시 upsert 할 수 있어야 한다(기록과 달리 툼스톤이 없다).
    func testRaceTargetCanBeReAddedAfterDeletion() throws {
        let ctrl = try makeController()
        let target = makeRaceTarget()

        try ctrl.upsertRaceTarget(target)
        try ctrl.deleteRaceTarget(id: target.id)
        try ctrl.upsertRaceTarget(target)

        XCTAssertEqual(try ctrl.fetchRaceTargets().count, 1)
    }
}
