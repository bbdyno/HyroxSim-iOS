import Foundation

/// Heart rate training zones based on percentage of max heart rate.
/// Zone boundaries: Z1 50–60% / Z2 60–70% / Z3 70–80% / Z4 80–90% / Z5 90–100%.
/// Below 50% clamps to Z1, above 100% clamps to Z5.
public enum HeartRateZone: Int, CaseIterable, Codable, Sendable {
    case z1 = 1, z2, z3, z4, z5

    /// Short label ("Z1" through "Z5")
    public var label: String { "Z\(rawValue)" }

    /// Descriptive name for the zone
    public var description: String {
        switch self {
        case .z1: return "Very Light"
        case .z2: return "Light"
        case .z3: return "Moderate"
        case .z4: return "Hard"
        case .z5: return "Maximum"
        }
    }

    /// Percentage range of max heart rate for this zone
    public var range: ClosedRange<Double> {
        switch self {
        case .z1: return 0.50...0.60
        case .z2: return 0.60...0.70
        case .z3: return 0.70...0.80
        case .z4: return 0.80...0.90
        case .z5: return 0.90...1.00
        }
    }

    /// Determines the heart rate zone for a given BPM and max heart rate.
    /// - Parameters:
    ///   - bpm: Current heart rate in beats per minute
    ///   - maxHeartRate: Maximum heart rate in beats per minute
    /// - Returns: The corresponding heart rate zone (clamped to Z1 below 50%, Z5 above 100%)
    public static func zone(forHeartRate bpm: Int, maxHeartRate: Int) -> HeartRateZone {
        guard maxHeartRate > 0 else { return .z1 }
        let percentage = Double(bpm) / Double(maxHeartRate)

        if percentage < 0.60 { return .z1 }
        if percentage < 0.70 { return .z2 }
        if percentage < 0.80 { return .z3 }
        if percentage < 0.90 { return .z4 }
        return .z5
    }
}
