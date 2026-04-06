import Foundation

/// Represents the target/goal for a station exercise.
/// Weight is handled separately via `WorkoutSegment.weightKg` since it varies by division.
public enum StationTarget: Codable, Hashable, Sendable {
    case distance(meters: Double)
    case reps(count: Int)
    case duration(seconds: TimeInterval)
    case none

    /// Human-readable formatted string
    public var formatted: String {
        switch self {
        case .distance(let meters):
            return "\(Int(meters)) m"
        case .reps(let count):
            return "\(count) reps"
        case .duration(let seconds):
            let mins = Int(seconds) / 60
            let secs = Int(seconds) % 60
            return String(format: "%02d:%02d", mins, secs)
        case .none:
            return "—"
        }
    }
}
