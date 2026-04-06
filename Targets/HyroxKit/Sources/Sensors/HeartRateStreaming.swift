import Foundation

/// Abstraction over a heart rate provider.
/// Implemented by platform-specific adapters (HealthKit on iOS, HKWorkoutSession on watchOS).
/// HyroxKit does NOT import HealthKit — this protocol keeps the boundary clean.
public protocol HeartRateStreaming: AnyObject, Sendable {
    /// Stream of heart rate samples. Values flow only after `start()`.
    var samples: AsyncStream<HeartRateSample> { get }

    /// Requests authorization (if needed) and begins heart rate monitoring.
    /// Idempotent — calling on an already-started stream is a no-op.
    func start() async throws

    /// Stops heart rate monitoring.
    func stop()

    /// Current authorization status.
    var authorizationStatus: SensorAuthorizationStatus { get }
}
