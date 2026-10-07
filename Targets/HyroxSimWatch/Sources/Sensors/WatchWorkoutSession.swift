//
//  WatchWorkoutSession.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import HealthKit
import HyroxCore

/// watchOS workout session adapter.
/// Manages HKWorkoutSession + HKLiveWorkoutBuilder and streams heart rate data.
///
/// This is both a sensor adapter (HeartRateStreaming) and the workout session host.
/// On watchOS, HKWorkoutSession guarantees background execution, heart rate streaming,
/// and proper lock-screen integration during active workouts.
///
/// Location is handled separately by CoreLocationAdapter — the workout session
/// keeps the app alive in the background so CoreLocation continues to deliver updates.
@MainActor
public final class WatchWorkoutSession: NSObject, @preconcurrency HeartRateStreaming, @unchecked Sendable {

    /// 이 세션을 왜 켜는지. 건강 앱에 운동을 남길지 말지를 가른다.
    public enum Purpose: Sendable {
        /// 워치가 운동 주체 — 종료 시 건강 앱에 운동을 저장한다.
        case recording
        /// 폰 운동을 미러링하며 심박만 중계 — 종료 시 기록을 폐기한다.
        /// 폰이 같은 운동을 건강 앱에 저장하므로, 여기서도 저장하면 같은 운동이 두 번 남는다.
        case heartRateRelay
    }

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    /// 기본값이 `.heartRateRelay` 인 것은 의도적이다 —
    /// 건강 앱 저장은 "운동을 실제로 기록하는" 한 곳(`WatchActiveWorkoutModel`)에서만 명시적으로 켠다.
    /// 새 호출자가 무심코 세션을 만들어도 중복 기록이 생기지 않는다.
    private let purpose: Purpose

    /// 세션 시작 시 적용할 실내/실외.
    /// `start()` 호출 전에만 의미가 있다 — `HKWorkoutConfiguration.locationType` 은 세션 생성 뒤 바꿀 수 없다.
    public var plannedEnvironment: WorkoutEnvironment = .indoor

    private var hrContinuation: AsyncStream<HeartRateSample>.Continuation?
    public let samples: AsyncStream<HeartRateSample>

    public private(set) var authorizationStatus: SensorAuthorizationStatus = .notDetermined
    public private(set) var cumulativeDistanceMeters: Double = 0
    private var isStarted = false

    /// 아직 builder 에 넣지 못한 구간 이벤트. 세션 시작 전 `advance` 가 일어나도 잃지 않는다.
    private var pendingSegmentEvents: [HealthWorkoutExport.SegmentEvent] = []
    /// 구간 이벤트 전송을 직렬화해 순서가 뒤엉키지 않게 한다.
    private var eventFlushTask: Task<Void, Never>?

    var onRemoteDataReceived: (([Data]) -> Void)?
    var onRemoteDisconnect: ((Error?) -> Void)?

    public init(purpose: Purpose = .heartRateRelay) {
        self.purpose = purpose
        var cont: AsyncStream<HeartRateSample>.Continuation!
        self.samples = AsyncStream(bufferingPolicy: .bufferingNewest(100)) { c in cont = c }
        super.init()
        self.hrContinuation = cont
    }

    deinit {
        hrContinuation?.finish()
    }

    // MARK: - HeartRateStreaming

    public func start() async throws {
        guard !isStarted else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SensorError.unavailable
        }

        let heartRateType = HKQuantityType(.heartRate)
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let workoutType = HKObjectType.workoutType()

        do {
            try await healthStore.requestAuthorization(
                toShare: [workoutType],
                read: [heartRateType, distanceType]
            )
        } catch {
            throw SensorError.startFailed(reason: error.localizedDescription)
        }

        authorizationStatus = .authorized

        // HYROX doesn't have a dedicated HKWorkoutActivityType.
        // .functionalStrengthTraining is the closest match — it covers mixed
        // cardio/strength formats. .crossTraining was also considered but
        // functionalStrengthTraining better represents the station-based nature.
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = plannedEnvironment.isIndoor ? .indoor : .outdoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
        } catch {
            throw SensorError.startFailed(reason: error.localizedDescription)
        }

        guard let session, let builder else {
            throw SensorError.startFailed(reason: "Failed to create workout session")
        }

        session.delegate = self
        builder.delegate = self

        let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        // `.functionalStrengthTraining` 의 기본 수집 목록에는 거리가 없다.
        // 명시적으로 켜야 실내 운동에서도 워치 모션 센서 기반 거리가 들어오고, 페이스가 "—" 로 남지 않는다.
        dataSource.enableCollection(for: distanceType, predicate: nil)
        builder.dataSource = dataSource

        let startDate = Date()
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)

        isStarted = true
        flushSegmentEvents()
    }

    public func stop() {
        end()
    }

    // MARK: - Segments & metadata

    /// 구간이 끝날 때마다 호출한다. 피트니스 앱에서 스플릿으로 보인다.
    /// 릴레이 전용 세션에서는 무시한다 — 저장하지 않는 기록에 이벤트를 넣을 이유가 없다.
    public func addSegmentEvent(_ event: HealthWorkoutExport.SegmentEvent) {
        guard purpose == .recording, event.duration > 0 else { return }
        pendingSegmentEvents.append(event)
        flushSegmentEvents()
    }

    private func flushSegmentEvents() {
        guard purpose == .recording, isStarted, let builder, !pendingSegmentEvents.isEmpty else { return }
        let previous = eventFlushTask
        eventFlushTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            let events = self.pendingSegmentEvents
            guard !events.isEmpty else { return }
            self.pendingSegmentEvents = []
            do {
                try await builder.addWorkoutEvents(Self.makeWorkoutEvents(events))
            } catch {
                // 실패한 이벤트는 되돌려 종료 시 다시 시도한다. 이벤트는 각자 기간을 들고 있어 순서는 상관없다.
                self.pendingSegmentEvents.append(contentsOf: events)
                print("[WatchWorkout] Failed to add segment events: \(error)")
            }
        }
    }

    /// 워크아웃 세션을 끝낸다.
    /// - `recording`: 남은 구간 이벤트와 메타데이터를 넣고 건강 앱에 저장한다.
    /// - `heartRateRelay`: `discardWorkout()` 으로 폐기한다 — 폰 운동과 중복 기록되지 않도록.
    public func end(metadata: HealthWorkoutMetadata? = nil) {
        guard isStarted else { return }
        isStarted = false
        session?.end()

        let builder = self.builder
        let purpose = self.purpose
        let flush = eventFlushTask

        Task { @MainActor [weak self] in
            await flush?.value
            guard let builder else { return }

            guard purpose == .recording else {
                builder.discardWorkout()
                return
            }

            // 진행 중 전송에 실패해 되돌아온 이벤트까지 포함해 마지막으로 한 번 더 시도한다.
            let pending = self?.pendingSegmentEvents ?? []
            self?.pendingSegmentEvents = []

            let endDate = Date()
            if !pending.isEmpty {
                do {
                    try await builder.addWorkoutEvents(Self.makeWorkoutEvents(pending))
                } catch {
                    print("[WatchWorkout] Failed to add trailing segment events: \(error)")
                }
            }
            if let metadata {
                do {
                    try await builder.addMetadata(Self.makeMetadata(metadata))
                } catch {
                    // 메타데이터가 빠져도 운동 자체는 저장되어야 한다.
                    print("[WatchWorkout] Failed to add workout metadata: \(error)")
                }
            }
            do {
                try await builder.endCollection(at: endDate)
                _ = try await builder.finishWorkout()
            } catch {
                print("[WatchWorkout] Failed to finish HealthKit workout: \(error)")
            }
        }
    }

    static func makeWorkoutEvents(_ events: [HealthWorkoutExport.SegmentEvent]) -> [HKWorkoutEvent] {
        events
            .filter { $0.duration > 0 }
            .sorted { $0.startedAt < $1.startedAt }
            .map {
                HKWorkoutEvent(
                    type: .segment,
                    dateInterval: DateInterval(start: $0.startedAt, end: $0.endedAt),
                    metadata: $0.metadata
                )
            }
    }

    static func makeMetadata(_ metadata: HealthWorkoutMetadata) -> [String: Any] {
        var values: [String: Any] = metadata.customValues
        // 피트니스 앱이 실내/실외를 읽는 표준 키. 세션 생성 뒤에는 locationType 을 바꿀 수 없어
        // 실측으로 확정된 값을 여기서 덮어쓴다.
        values[HKMetadataKeyIndoorWorkout] = NSNumber(value: metadata.isIndoor)
        return values
    }

    // MARK: - Mirroring

    func startMirroringToCompanionDevice() async throws {
        guard let session else {
            throw SensorError.startFailed(reason: "Workout session unavailable")
        }
        try await session.startMirroringToCompanionDevice()
    }

    func sendToRemoteWorkoutSession(data: Data) async throws {
        guard let session else {
            throw SensorError.startFailed(reason: "Workout session unavailable")
        }
        try await session.sendToRemoteWorkoutSession(data: data)
    }

    /// Pauses the HKWorkoutSession (separate from WorkoutEngine.pause).
    /// The caller is responsible for synchronizing these.
    public func pause() {
        session?.pause()
    }

    /// Resumes the HKWorkoutSession (separate from WorkoutEngine.resume).
    public func resume() {
        session?.resume()
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutSession: HKWorkoutSessionDelegate {

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // State transitions are logged but not acted upon in this version.
        // Future: notify UI of session state changes.
    }

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        // Non-fatal — session may recover.
    }

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor [weak self] in
            self?.onRemoteDataReceived?(data)
        }
    }

    nonisolated public func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.onRemoteDisconnect?(error)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutSession: HKLiveWorkoutBuilderDelegate {

    nonisolated public func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // Workout events (pause/resume markers) — no action needed in v1.
    }

    nonisolated public func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let heartRateType = HKQuantityType(.heartRate)
        let distanceType = HKQuantityType(.distanceWalkingRunning)

        Task { @MainActor [weak self] in
            if collectedTypes.contains(heartRateType) {
                let statistics = workoutBuilder.statistics(for: heartRateType)
                if let mostRecentQuantity = statistics?.mostRecentQuantity() {
                    let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                    let bpm = Int(mostRecentQuantity.doubleValue(for: bpmUnit))
                    self?.hrContinuation?.yield(HeartRateSample(timestamp: Date(), bpm: bpm))
                }
            }

            if collectedTypes.contains(distanceType) {
                let statistics = workoutBuilder.statistics(for: distanceType)
                if let sumQuantity = statistics?.sumQuantity() {
                    self?.cumulativeDistanceMeters = sumQuantity.doubleValue(for: .meter())
                }
            }
        }
    }
}
