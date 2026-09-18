//
//  ActiveWorkoutViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxCore
import HyroxPersistenceApple
@testable import HyroxSim

/// `start()` 이 실패하는 위치 스트림 (권한 거부 시나리오).
final class DeniedLocationStream: LocationStreaming, @unchecked Sendable {
    let samples: AsyncStream<LocationSample>
    private(set) var authorizationStatus: SensorAuthorizationStatus = .denied
    private(set) var startCallCount = 0

    init() {
        self.samples = AsyncStream { _ in }
    }

    func start() async throws {
        startCallCount += 1
        throw SensorError.authorizationDenied
    }

    func stop() {}
}

/// `start()` 이 실패하는 심박 스트림.
final class FailingHeartRateStream: HeartRateStreaming, @unchecked Sendable {
    let samples: AsyncStream<HeartRateSample>
    private(set) var authorizationStatus: SensorAuthorizationStatus = .denied

    init() {
        self.samples = AsyncStream { _ in }
    }

    func start() async throws { throw SensorError.unavailable }
    func stop() {}
}

@MainActor
final class ActiveWorkoutViewModelTests: XCTestCase {

    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    /// 테스트끼리, 그리고 실제 앱 체크포인트와 섞이지 않도록 임시 디렉터리를 쓴다.
    private func makeTemporaryCheckpointStore() throws -> WorkoutCheckpointStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkpoint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return WorkoutCheckpointStore(directory: url)
    }

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
            maxHeartRate: 200,
            checkpointStore: try makeTemporaryCheckpointStore()
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

    // MARK: - Sensor failures (P1: 권한 거부해도 운동은 계속되어야 함)

    func testWorkoutRunsWhenLocationPermissionDenied() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let location = DeniedLocationStream()
        let vm = ActiveWorkoutViewModel(
            template: WorkoutTemplate(name: "Test", segments: [.run(), .roxZone()]),
            locationStream: location,
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            checkpointStore: try makeTemporaryCheckpointStore()
        )

        var reportedError: Error?
        vm.errorHandler = { reportedError = $0 }

        await vm.start()

        // 운동은 정상 진행 + GPS 만 비활성
        XCTAssertEqual(vm.segmentLabel, "RUN 1 / 1")
        XCTAssertEqual(vm.gpsStatus, .off)
        XCTAssertFalse(vm.isFinished)
        XCTAssertEqual(reportedError as? SensorError, .authorizationDenied)
        XCTAssertEqual(location.startCallCount, 1)

        // 엔진도 살아 있어야 한다 — 다음 세그먼트로 넘어갈 수 있는지 확인
        vm.advance()
        XCTAssertEqual(vm.segmentLabel, "ROX ZONE")
        vm.cancelWorkout()
    }

    func testWorkoutRunsWhenBothSensorsFail() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let vm = ActiveWorkoutViewModel(
            template: WorkoutTemplate(name: "Test", segments: [.run()]),
            locationStream: DeniedLocationStream(),
            heartRateStream: FailingHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            checkpointStore: try makeTemporaryCheckpointStore()
        )

        var errorCount = 0
        vm.errorHandler = { _ in errorCount += 1 }

        await vm.start()

        XCTAssertEqual(vm.segmentLabel, "RUN 1 / 1")
        XCTAssertEqual(vm.heartRateText, "—")
        // 알럿이 겹쳐 뜨지 않도록 대표 오류 하나만 보고한다.
        XCTAssertEqual(errorCount, 1)
        vm.cancelWorkout()
    }

    // MARK: - Checkpoint (P1: 중간 저장)

    func testCheckpointIsWrittenOnStartAndAdvance() async throws {
        let store = try makeTemporaryCheckpointStore()
        let persistence = try PersistenceController(inMemory: true)
        let vm = ActiveWorkoutViewModel(
            template: WorkoutTemplate(name: "Checkpointed", segments: [.run(), .roxZone(), .station(.skiErg)]),
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            checkpointStore: store
        )

        await vm.start()
        let afterStart = store.load()
        XCTAssertEqual(afterStart?.workout.templateName, "Checkpointed")
        XCTAssertEqual(afterStart?.workout.segments.count, 1)

        vm.advance()
        let afterAdvance = store.load()
        XCTAssertEqual(afterAdvance?.workout.segments.count, 2)
        // 같은 운동은 같은 id 로 저장돼야 복구가 idempotent 하다.
        XCTAssertEqual(afterAdvance?.workout.id, afterStart?.workout.id)

        vm.cancelWorkout()
        XCTAssertNil(store.load())
    }

    func testCheckpointIsClearedAfterSuccessfulSave() async throws {
        let store = try makeTemporaryCheckpointStore()
        let persistence = try PersistenceController(inMemory: true)
        let vm = ActiveWorkoutViewModel(
            template: WorkoutTemplate(name: "Test", segments: [.run(), .station(.skiErg)]),
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            checkpointStore: store
        )

        let expectation = XCTestExpectation(description: "finish called")
        vm.finishHandler = { (_: CompletedWorkout) in expectation.fulfill() }

        await vm.start()
        XCTAssertNotNil(store.load())

        vm.endWorkout()
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertNil(store.load())
        XCTAssertEqual(try persistence.fetchAllCompletedWorkouts().count, 1)
    }

    func testCheckpointStoreRoundTripAndClear() throws {
        let store = try makeTemporaryCheckpointStore()
        XCTAssertNil(store.load())

        let workout = CompletedWorkout(
            templateName: "Round trip",
            startedAt: Date(timeIntervalSince1970: 1_000),
            finishedAt: Date(timeIntervalSince1970: 1_600),
            segments: []
        )
        store.save(workout: workout)

        let loaded = store.load()
        XCTAssertEqual(loaded?.workout.id, workout.id)
        XCTAssertEqual(loaded?.workout.totalDuration, 600)

        store.clear()
        XCTAssertNil(store.load())
    }
}
