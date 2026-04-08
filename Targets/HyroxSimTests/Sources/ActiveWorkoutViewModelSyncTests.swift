//
//  ActiveWorkoutViewModelSyncTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/8/26.
//

import XCTest
@testable import HyroxKit
@testable import HyroxSim

@MainActor
final class ActiveWorkoutViewModelSyncTests: XCTestCase {

    private func makeVM(syncCoordinator: MockSyncCoordinator? = nil) throws -> (ActiveWorkoutViewModel, MockSyncCoordinator) {
        let sync = syncCoordinator ?? MockSyncCoordinator()
        let template = WorkoutTemplate(
            name: "Test",
            segments: [
                .run(distanceMeters: 1000),
                .roxZone(),
                .station(.skiErg, target: .distance(meters: 1000))
            ]
        )
        let persistence = try PersistenceController(inMemory: true)
        let vm = ActiveWorkoutViewModel(
            template: template,
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            syncCoordinator: sync
        )
        return (vm, sync)
    }

    // MARK: - Workout Start

    func testStartBroadcastsWorkoutStarted() async throws {
        let (vm, sync) = try makeVM()
        await vm.start()

        XCTAssertEqual(sync.sentWorkoutStarted.count, 1)
        XCTAssertEqual(sync.sentWorkoutStarted[0].origin, .phone)
        XCTAssertEqual(sync.sentWorkoutStarted[0].template.name, "Test")
    }

    func testStartSetsUpRemoteCommandCallback() async throws {
        let (vm, sync) = try makeVM()
        await vm.start()

        // onReceiveCommand should be set
        XCTAssertNotNil(sync.onReceiveCommand)
    }

    // MARK: - Live State Broadcasting

    func testRefreshBroadcastsLiveState() async throws {
        let (vm, sync) = try makeVM()
        await vm.start()

        // start() calls refresh() which calls broadcastLiveState()
        XCTAssertFalse(sync.sentLiveStates.isEmpty)

        let state = sync.sentLiveStates.last!
        XCTAssertEqual(state.origin, .phone)
        XCTAssertEqual(state.segmentLabel, "RUN 1 / 1")
        XCTAssertEqual(state.templateName, "Test")
        XCTAssertFalse(state.isPaused)
        XCTAssertFalse(state.isFinished)
    }

    // MARK: - Remote Command Handling

    func testRemoteCommandAdvance() async throws {
        let (vm, sync) = try makeVM()
        await vm.start()
        sync.sentLiveStates.removeAll()

        // Simulate watch sending advance command
        sync.onReceiveCommand?(.advance)

        XCTAssertEqual(vm.segmentLabel, "ROX ZONE")
        XCTAssertFalse(sync.sentLiveStates.isEmpty)
    }

    func testRemoteCommandPause() async throws {
        let (vm, sync) = try makeVM()
        await vm.start()

        sync.onReceiveCommand?(.pause)
        XCTAssertTrue(vm.isPaused)

        // Sending pause again when already paused should not toggle
        sync.onReceiveCommand?(.pause)
        XCTAssertTrue(vm.isPaused)
    }

    func testRemoteCommandResume() async throws {
        let (vm, sync) = try makeVM()
        await vm.start()

        sync.onReceiveCommand?(.pause)
        XCTAssertTrue(vm.isPaused)

        sync.onReceiveCommand?(.resume)
        XCTAssertFalse(vm.isPaused)
    }

    func testRemoteCommandEnd() async throws {
        let (vm, sync) = try makeVM()
        var finishCalled = false
        vm.finishHandler = { _ in finishCalled = true }
        await vm.start()

        sync.onReceiveCommand?(.end)

        // Give time for async finishAndSave
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(finishCalled)
    }

    // MARK: - HR Relay

    func testHeartRateRelayIngestsIntoEngine() async throws {
        let (vm, sync) = try makeVM()
        await vm.start()

        // Simulate watch sending HR relay
        let relay = HeartRateRelay(bpm: 165, timestamp: Date())
        sync.onHeartRateRelayReceived?(relay)

        // Trigger refresh to pick up the ingested HR
        vm.refresh()
        XCTAssertEqual(vm.heartRateText, "165")
    }

    // MARK: - Workout Finish

    func testFinishBroadcastsWorkoutFinished() async throws {
        let (vm, sync) = try makeVM()
        vm.finishHandler = { _ in }
        await vm.start()

        vm.endWorkout()

        // Give time for async finishAndSave
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(sync.sentWorkoutFinished, [.phone])
    }

    // MARK: - No Sync Coordinator

    func testWorkoutWithoutSyncCoordinator() async throws {
        let template = WorkoutTemplate(
            name: "NoSync",
            segments: [.run(distanceMeters: 1000)]
        )
        let persistence = try PersistenceController(inMemory: true)
        let vm = ActiveWorkoutViewModel(
            template: template,
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence
        )
        // Should work without sync coordinator (no crash)
        await vm.start()
        XCTAssertEqual(vm.segmentLabel, "RUN 1 / 1")
    }

    // MARK: - Cleanup

    func testCleanupNilsCallbacks() async throws {
        let (vm, sync) = try makeVM()
        vm.finishHandler = { _ in }
        await vm.start()

        XCTAssertNotNil(sync.onReceiveCommand)

        vm.endWorkout()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertNil(sync.onReceiveCommand)
        XCTAssertNil(sync.onHeartRateRelayReceived)
    }
}
