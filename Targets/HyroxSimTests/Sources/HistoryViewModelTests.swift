//
//  HistoryViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxCore
import HyroxPersistenceApple
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

        try vm.delete(at: 0)
        XCTAssertEqual(vm.workouts.count, 1)
        XCTAssertEqual(vm.workouts[0].id, w1.id)
    }

    /// 삭제가 실패하면 목록은 그대로여야 한다.
    /// 예전에는 `try?` 라 실패해도 행이 사라졌다가 다음 진입에 되살아났다.
    func testDeleteFailureKeepsRow() throws {
        let persistence = try makePersistence()
        let w1 = makeWorkout(finishedAtOffset: 100)
        try persistence.saveCompletedWorkout(w1)

        let vm = HistoryViewModel(persistence: persistence)
        vm.load()
        XCTAssertEqual(vm.workouts.count, 1)

        // 뷰모델이 들고 있는 동안 저장소에서 사라진 상태를 만든다 →
        // 다음 삭제는 notFound 로 실패한다.
        try persistence.deleteCompletedWorkout(id: w1.id)

        XCTAssertThrowsError(try vm.delete(at: 0))
        XCTAssertEqual(vm.workouts.count, 1, "삭제에 실패했으면 행을 되돌려야 한다")
    }

    func testDeleteOutOfRangeIsIgnored() throws {
        let vm = HistoryViewModel(persistence: try makePersistence())
        vm.load()
        XCTAssertNoThrow(try vm.delete(at: 5))
    }

    /// 워치·가민에서 기록이 도착하면 목록이 자동으로 갱신된다.
    func testSyncNotificationReloadsList() async throws {
        let persistence = try makePersistence()
        let center = NotificationCenter()
        let vm = HistoryViewModel(persistence: persistence, notificationCenter: center)
        vm.reloadDebounce = .zero
        vm.load()
        XCTAssertTrue(vm.workouts.isEmpty)

        let reloaded = expectation(description: "list reloaded")
        vm.onWorkoutsChanged = { reloaded.fulfill() }
        vm.startObserving()

        // 동기화로 기록이 들어온 상황을 흉내 낸다.
        try persistence.saveCompletedWorkout(makeWorkout(finishedAtOffset: 100))
        center.post(name: .syncDataUpdated, object: nil)

        await fulfillment(of: [reloaded], timeout: 2)
        XCTAssertEqual(vm.workouts.count, 1)
        vm.stopObserving()
    }

    /// 원격 삭제가 전파돼도 목록이 따라간다.
    func testDeletedNotificationReloadsList() async throws {
        let persistence = try makePersistence()
        let center = NotificationCenter()
        let workout = makeWorkout(finishedAtOffset: 100)
        try persistence.saveCompletedWorkout(workout)

        let vm = HistoryViewModel(persistence: persistence, notificationCenter: center)
        vm.reloadDebounce = .zero
        vm.load()
        XCTAssertEqual(vm.workouts.count, 1)

        let reloaded = expectation(description: "list reloaded")
        vm.onWorkoutsChanged = { reloaded.fulfill() }
        vm.startObserving()

        _ = try persistence.applyRemoteCompletedWorkoutDeletion(id: workout.id)
        center.post(
            name: .hyroxCompletedWorkoutDeleted,
            object: nil,
            userInfo: [PersistenceController.deletedWorkoutIdKey: workout.id]
        )

        await fulfillment(of: [reloaded], timeout: 2)
        XCTAssertTrue(vm.workouts.isEmpty)
        vm.stopObserving()
    }

    /// 알림이 몰려 와도 한 번만 새로고침한다.
    func testBurstOfNotificationsReloadsOnce() async throws {
        let persistence = try makePersistence()
        let center = NotificationCenter()
        let vm = HistoryViewModel(persistence: persistence, notificationCenter: center)
        vm.reloadDebounce = .milliseconds(80)
        vm.startObserving()

        var reloadCount = 0
        let reloaded = expectation(description: "list reloaded")
        vm.onWorkoutsChanged = {
            reloadCount += 1
            reloaded.fulfill()
        }

        for _ in 0..<5 {
            center.post(name: .syncDataUpdated, object: nil)
        }

        await fulfillment(of: [reloaded], timeout: 2)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(reloadCount, 1)
        vm.stopObserving()
    }
}
