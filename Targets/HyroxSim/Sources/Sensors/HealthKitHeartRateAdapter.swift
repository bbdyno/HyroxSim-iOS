//
//  HealthKitHeartRateAdapter.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import HealthKit
import HyroxCore

/// HealthKit heart rate adapter for iOS.
/// Uses HKAnchoredObjectQuery to observe heart rate samples.
///
/// **Limitation**: On iOS (phone), heart rate data comes from Apple Watch sync
/// which may have a delay. For real-time HR during workouts, the watchOS
/// WatchWorkoutSession adapter is preferred. This adapter is a fallback
/// for scenarios where the phone is the primary device.
public final class HealthKitHeartRateAdapter: HeartRateStreaming, @unchecked Sendable {

    private let healthStore = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?
    private var continuation: AsyncStream<HeartRateSample>.Continuation?
    public let samples: AsyncStream<HeartRateSample>

    public private(set) var authorizationStatus: SensorAuthorizationStatus = .notDetermined
    private var isStarted = false

    public init() {
        var cont: AsyncStream<HeartRateSample>.Continuation!
        self.samples = AsyncStream(bufferingPolicy: .bufferingNewest(100)) { c in cont = c }
        self.continuation = cont
    }

    deinit {
        continuation?.finish()
    }

    // MARK: - HeartRateStreaming

    public func start() async throws {
        guard !isStarted else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw SensorError.unavailable
        }

        let heartRateType = HKQuantityType(.heartRate)

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [heartRateType])
        } catch {
            throw SensorError.startFailed(reason: error.localizedDescription)
        }

        // Check read authorization — HealthKit doesn't expose read status directly,
        // so we proceed optimistically. If access is denied, the query returns no results.
        authorizationStatus = .authorized

        // Only fetch samples from now onward to avoid stale historical data
        let startPredicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: startPredicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.processSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.processSamples(samples)
        }

        healthStore.execute(query)
        self.query = query
        isStarted = true
    }

    public func stop() {
        if let query {
            healthStore.stop(query)
        }
        query = nil
        isStarted = false
    }

    // MARK: - Private

    private func processSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        for sample in quantitySamples {
            let bpm = Int(sample.quantity.doubleValue(for: bpmUnit))
            let hrSample = HeartRateSample(timestamp: sample.startDate, bpm: bpm)
            continuation?.yield(hrSample)
        }
    }
}
