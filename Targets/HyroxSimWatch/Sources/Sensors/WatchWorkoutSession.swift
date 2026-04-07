//
//  WatchWorkoutSession.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import HealthKit
import HyroxKit

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

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var hrContinuation: AsyncStream<HeartRateSample>.Continuation?
    public let samples: AsyncStream<HeartRateSample>

    public private(set) var authorizationStatus: SensorAuthorizationStatus = .notDetermined
    public private(set) var cumulativeDistanceMeters: Double = 0
    private var isStarted = false

    public override init() {
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
        config.locationType = .outdoor

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
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

        let startDate = Date()
        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)

        isStarted = true
    }

    public func stop() {
        guard isStarted else { return }
        session?.end()

        Task {
            if let builder {
                let endDate = Date()
                try? await builder.endCollection(at: endDate)
                _ = try? await builder.finishWorkout()
            }
        }

        isStarted = false
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
