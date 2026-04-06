import Foundation

/// Errors thrown by sensor adapters
public enum SensorError: Error, Hashable, Sendable {
    /// User denied the required permission
    case authorizationDenied
    /// The sensor or capability is not available on this device
    case unavailable
    /// Sensor failed to start for a specific reason
    case startFailed(reason: String)
}
