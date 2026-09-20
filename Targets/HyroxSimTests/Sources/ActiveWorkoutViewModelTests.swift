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

/// 건강 앱 저장을 대신 받는 모의 객체. HealthKit 은 시뮬레이터에서 검증이 어려워
/// 저장 로직을 `HealthWorkoutSaving` 뒤로 분리하고 이 객체로 호출을 관찰한다.
final class MockHealthWorkoutSaver: HealthWorkoutSaving, @unchecked Sendable {
    /// `requestAuthorization()` 이 돌려줄 값. false 면 뷰모델은 저장을 건너뛰어야 한다.
    var authorizationResult: Bool
    /// `save(_:)` 가 던질 오류. 저장 실패가 사용자 흐름을 막지 않는지 확인할 때 쓴다.
    var saveError: Error?
    var isAvailable: Bool = true

    private(set) var requestAuthorizationCallCount = 0
    private(set) var savedExports: [HealthWorkoutExport] = []
    /// 저장 시도(성공·실패 모두) 직후 호출. 테스트가 비동기 저장 완료를 기다릴 때 쓴다.
    var onSaveAttempt: (@Sendable () -> Void)?

    init(authorizationResult: Bool = true, saveError: Error? = nil) {
        self.authorizationResult = authorizationResult
        self.saveError = saveError
    }

    func requestAuthorization() async -> Bool {
        requestAuthorizationCallCount += 1
        return authorizationResult
    }

    func save(_ export: HealthWorkoutExport) async throws {
        if let saveError {
            onSaveAttempt?()
            throw saveError
        }
        savedExports.append(export)
        onSaveAttempt?()
    }
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
            checkpointStore: try makeTemporaryCheckpointStore(),
            healthWorkoutSaver: MockHealthWorkoutSaver()
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
            maxHeartRate: 200,
            healthWorkoutSaver: MockHealthWorkoutSaver()
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
            maxHeartRate: 200,
            healthWorkoutSaver: MockHealthWorkoutSaver()
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
            checkpointStore: try makeTemporaryCheckpointStore(),
            healthWorkoutSaver: MockHealthWorkoutSaver()
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
            checkpointStore: try makeTemporaryCheckpointStore(),
            healthWorkoutSaver: MockHealthWorkoutSaver()
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
            checkpointStore: store,
            healthWorkoutSaver: MockHealthWorkoutSaver()
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
            checkpointStore: store,
            healthWorkoutSaver: MockHealthWorkoutSaver()
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

    // MARK: - Health 앱 저장

    private func makeVM(
        segments: [WorkoutSegment],
        persistence: PersistenceController,
        saver: MockHealthWorkoutSaver
    ) throws -> ActiveWorkoutViewModel {
        ActiveWorkoutViewModel(
            template: WorkoutTemplate(name: "Health test", segments: segments),
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            checkpointStore: try makeTemporaryCheckpointStore(),
            healthWorkoutSaver: saver
        )
    }

    /// 폰 단독 운동이 끝나면 건강 앱에도 저장된다. 구간 이벤트는 기록된 세그먼트 수와 같다.
    func testCompletedPhoneWorkoutIsSavedToHealth() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let saver = MockHealthWorkoutSaver()
        let vm = try makeVM(
            segments: [.run(), .roxZone(), .station(.skiErg)],
            persistence: persistence,
            saver: saver
        )

        let saveAttempted = XCTestExpectation(description: "health save attempted")
        saver.onSaveAttempt = { saveAttempted.fulfill() }

        await vm.start()
        vm.endWorkout()
        await fulfillment(of: [saveAttempted], timeout: 2)

        XCTAssertEqual(saver.requestAuthorizationCallCount, 1)
        XCTAssertEqual(saver.savedExports.count, 1)

        let export = try XCTUnwrap(saver.savedExports.first)
        // 폰에서 시작한 운동만 폰이 저장한다 — 워치 기록과 중복되지 않도록.
        XCTAssertEqual(export.origin, .phone)
        XCTAssertEqual(export.templateName, "Health test")
        // endWorkout 은 현재 구간 하나만 기록하므로 구간 이벤트도 하나.
        XCTAssertEqual(export.segmentEvents.count, 1)
        XCTAssertEqual(export.segmentEvents.first?.title, "RUN 1")
        // GPS 샘플이 없으면 이동을 확인할 수 없어 실내로 기록한다.
        XCTAssertTrue(export.isIndoor)
    }

    /// 31 구간을 모두 진행하면 구간 이벤트도 31개.
    func testHealthSegmentEventCountMatchesSegmentCount() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let saver = MockHealthWorkoutSaver()
        let segments: [WorkoutSegment] = [.run(), .roxZone(), .station(.skiErg), .roxZone()]
        let vm = try makeVM(segments: segments, persistence: persistence, saver: saver)

        let saveAttempted = XCTestExpectation(description: "health save attempted")
        saver.onSaveAttempt = { saveAttempted.fulfill() }

        await vm.start()
        // 구간 길이가 0 이면 HealthKit 이 이벤트를 받지 않으므로 최소 간격을 둔다.
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(10))
            vm.advance()
        }
        await fulfillment(of: [saveAttempted], timeout: 2)

        let export = try XCTUnwrap(saver.savedExports.first)
        XCTAssertEqual(export.segmentEvents.count, segments.count)
        XCTAssertEqual(
            export.segmentEvents.map(\.title),
            ["RUN 1", "ROX ZONE", "SkiErg", "ROX ZONE"]
        )
    }

    /// 쓰기 권한을 거부하면 조용히 건너뛴다. 운동 자체와 로컬 저장은 그대로 진행된다.
    func testHealthSaveIsSkippedWhenAuthorizationDenied() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let saver = MockHealthWorkoutSaver(authorizationResult: false)
        let vm = try makeVM(segments: [.run()], persistence: persistence, saver: saver)

        let finished = XCTestExpectation(description: "finish called")
        vm.finishHandler = { (_: CompletedWorkout) in finished.fulfill() }

        await vm.start()
        vm.endWorkout()
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(saver.requestAuthorizationCallCount, 1)
        XCTAssertTrue(saver.savedExports.isEmpty)
        XCTAssertEqual(try persistence.fetchAllCompletedWorkouts().count, 1)
    }

    /// 건강 앱 저장이 실패해도 요약 화면·로컬 저장은 막히지 않는다.
    func testHealthSaveFailureDoesNotBlockWorkoutFlow() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let saver = MockHealthWorkoutSaver(saveError: HealthWorkoutSaveError.saveFailed(reason: "boom"))
        let vm = try makeVM(segments: [.run()], persistence: persistence, saver: saver)

        let finished = XCTestExpectation(description: "finish called")
        vm.finishHandler = { (_: CompletedWorkout) in finished.fulfill() }
        let saveAttempted = XCTestExpectation(description: "health save attempted")
        saver.onSaveAttempt = { saveAttempted.fulfill() }

        var reportedErrors: [Error] = []
        vm.errorHandler = { reportedErrors.append($0) }

        await vm.start()
        vm.endWorkout()
        await fulfillment(of: [finished, saveAttempted], timeout: 2)

        XCTAssertTrue(vm.isFinished)
        XCTAssertEqual(try persistence.fetchAllCompletedWorkouts().count, 1)
        // 저장 실패는 로그만 남긴다 — 사용자에게 알럿을 띄우지 않는다.
        XCTAssertTrue(reportedErrors.isEmpty)
    }

    /// 취소한 운동은 건강 앱에 남기지 않는다.
    func testCancelledWorkoutIsNotSavedToHealth() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let saver = MockHealthWorkoutSaver()
        let vm = try makeVM(segments: [.run(), .station(.skiErg)], persistence: persistence, saver: saver)

        await vm.start()
        vm.cancelWorkout()

        XCTAssertTrue(saver.savedExports.isEmpty)
        XCTAssertEqual(try persistence.fetchAllCompletedWorkouts().count, 0)
    }

    /// 저장 어댑터가 없으면(기기 미지원 등) 권한 요청도 저장도 하지 않고 운동만 진행한다.
    func testWorkoutRunsWithoutHealthSaver() async throws {
        let persistence = try PersistenceController(inMemory: true)
        let vm = ActiveWorkoutViewModel(
            template: WorkoutTemplate(name: "No health", segments: [.run()]),
            locationStream: MockLocationStream(),
            heartRateStream: MockHeartRateStream(),
            persistence: persistence,
            maxHeartRate: 200,
            checkpointStore: try makeTemporaryCheckpointStore(),
            healthWorkoutSaver: nil
        )

        let finished = XCTestExpectation(description: "finish called")
        vm.finishHandler = { (_: CompletedWorkout) in finished.fulfill() }

        await vm.start()
        vm.endWorkout()
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(try persistence.fetchAllCompletedWorkouts().count, 1)
    }
}
