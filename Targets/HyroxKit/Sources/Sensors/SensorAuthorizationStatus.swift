import Foundation

/// Platform-agnostic authorization status for a sensor.
/// Adapters map platform-specific statuses (CLAuthorizationStatus, HKAuthorizationStatus) to this.
public enum SensorAuthorizationStatus: Hashable, Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}
