//
//  ActiveWorkoutViewModelSyncTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/8/26.
//

import XCTest
@testable import HyroxCore
import HyroxPersistenceApple
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
            syncCoordinator: sync,
            healthWorkoutSaver: MockHealthWorkoutSaver()
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

    // MARK: - Sensor failure (P1)

    /// 위치 권한이 거부돼도 워치 전송(운동 시작 알림 + 실시간 상태)은 계속돼야 한다.
    func testBroadcastsContinueWhenLocationStartFails() async throws {
        let sync = MockSyncCoordinator()
        let persistence = try PersistenceController(inMemory: true)
        let checkpointDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkpoint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: checkpointDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: checkpointDirectory) }

        let vm = ActiveWorkoutViewModel(
            template: WorkoutTemplate(name: "Denied", segments: [.run(distanceMeters: 1000), .roxZone()]),
            locationStream: DeniedLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            syncCoordinator: sync,
            checkpointStore: WorkoutCheckpointStore(directory: checkpointDirectory),
            healthWorkoutSaver: MockHealthWorkoutSaver()
        )
        vm.errorHandler = { _ in }

        await vm.start()

        XCTAssertEqual(sync.sentWorkoutStarted.count, 1)
        let state = try XCTUnwrap(sync.sentLiveStates.last)
        XCTAssertEqual(state.segmentLabel, "RUN 1 / 1")
        XCTAssertFalse(state.gpsActive)
        XCTAssertFalse(state.gpsStrong)

        vm.cancelWorkout()
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
            persistence: persistence,
            healthWorkoutSaver: MockHealthWorkoutSaver()
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

// MARK: - 레이스 데이 (랩 카운터 · 다음 목표)

/// 운동 화면의 레이스 모드 표시가 기존 운동 흐름을 건드리지 않는지 확인한다.
/// 랩 수는 기록에 남지 않는 화면 보조 정보라, 검증 대상은 "화면 상태"뿐이다.
@MainActor
final class ActiveWorkoutViewModelRaceDayTests: XCTestCase {

    /// Run(360) → Rox(30) → SkiErg(240) — 기본 프리셋과 같은 한 블록.
    private func makeVM() throws -> ActiveWorkoutViewModel {
        let template = WorkoutTemplate(
            name: "Race",
            segments: [
                .run(distanceMeters: 1000),
                .roxZone(),
                .station(.skiErg, target: .distance(meters: 1000))
            ]
        )
        return ActiveWorkoutViewModel(
            template: template,
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: try PersistenceController(inMemory: true),
            maxHeartRate: 200,
            healthWorkoutSaver: MockHealthWorkoutSaver()
        )
    }

    // MARK: 랩 카운터

    func testLapCounterIncrements() async throws {
        let vm = try makeVM()
        await vm.start()

        vm.incrementLap()
        vm.incrementLap()

        XCTAssertEqual(vm.lapCount, 2)
        vm.cancelWorkout()
    }

    /// 잘못 눌러도 음수가 되면 안 된다.
    func testLapCounterStopsAtZero() async throws {
        let vm = try makeVM()
        await vm.start()

        vm.incrementLap()
        vm.decrementLap()
        vm.decrementLap()

        XCTAssertEqual(vm.lapCount, 0)
        vm.cancelWorkout()
    }

    func testLapCounterResetsOnSegmentChange() async throws {
        let vm = try makeVM()
        await vm.start()

        vm.incrementLap()
        vm.incrementLap()
        XCTAssertEqual(vm.lapCount, 2)

        vm.advance() // Run → ROX Zone

        XCTAssertEqual(vm.lapCount, 0)
        vm.cancelWorkout()
    }

    /// 랩은 런에서만 의미가 있다.
    func testLapCounterAvailabilityFollowsSegmentType() async throws {
        let vm = try makeVM()
        await vm.start()

        XCTAssertTrue(vm.isLapCounterAvailable)

        vm.advance() // ROX Zone
        XCTAssertFalse(vm.isLapCounterAvailable)

        vm.advance() // SkiErg
        XCTAssertFalse(vm.isLapCounterAvailable)

        vm.cancelWorkout()
    }

    // MARK: 레이스 모드

    func testRaceModeTogglesWithoutTouchingWorkoutState() async throws {
        let vm = try makeVM()
        let original = vm.isRaceMode
        defer { vm.setRaceMode(original) }

        await vm.start()
        let labelBefore = vm.segmentLabel

        vm.setRaceMode(!original)

        XCTAssertEqual(vm.isRaceMode, !original)
        XCTAssertEqual(vm.segmentLabel, labelBefore)
        XCTAssertFalse(vm.isFinished)
        vm.cancelWorkout()
    }

    // MARK: 다음 구간 목표 (Live Activity)

    /// 전환 구간은 건너뛰고 다음 "실제" 구간을 가리킨다.
    func testNextTargetSkipsRoxZone() async throws {
        let vm = try makeVM()
        await vm.start()

        XCTAssertEqual(vm.nextTargetLabel, "SkiErg")
        XCTAssertEqual(vm.nextTargetGoalText, "04:00")

        vm.advance() // ROX Zone 진행 중에도 다음은 여전히 스테이션
        XCTAssertEqual(vm.nextTargetLabel, "SkiErg")

        vm.cancelWorkout()
    }

    func testNextTargetIsEmptyOnLastSegment() async throws {
        let vm = try makeVM()
        await vm.start()

        vm.advance() // ROX Zone
        vm.advance() // SkiErg (마지막)

        XCTAssertTrue(vm.isLastSegment)
        XCTAssertNil(vm.nextTargetLabel)
        XCTAssertNil(vm.nextTargetGoalText)

        vm.cancelWorkout()
    }
}
