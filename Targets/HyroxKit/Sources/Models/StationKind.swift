import Foundation

/// Represents the kind of exercise station in a HYROX workout.
/// Standard 8 stations plus custom support.
public enum StationKind: Codable, Hashable, Sendable {
    case skiErg
    case sledPush
    case sledPull
    case burpeeBroadJumps
    case rowing
    case farmersCarry
    case sandbagLunges
    case wallBalls
    case custom(name: String)

    /// Display name for the station
    public var displayName: String {
        switch self {
        case .skiErg: return "SkiErg"
        case .sledPush: return "Sled Push"
        case .sledPull: return "Sled Pull"
        case .burpeeBroadJumps: return "Burpee Broad Jumps"
        case .rowing: return "Rowing"
        case .farmersCarry: return "Farmers Carry"
        case .sandbagLunges: return "Sandbag Lunges"
        case .wallBalls: return "Wall Balls"
        case .custom(let name): return name
        }
    }

    /// Default target for this station (division-independent)
    public var defaultTarget: StationTarget {
        switch self {
        case .skiErg: return .distance(meters: 1000)
        case .sledPush: return .distance(meters: 50)
        case .sledPull: return .distance(meters: 50)
        case .burpeeBroadJumps: return .distance(meters: 80)
        case .rowing: return .distance(meters: 1000)
        case .farmersCarry: return .distance(meters: 200)
        case .sandbagLunges: return .distance(meters: 100)
        case .wallBalls: return .reps(count: 100)
        case .custom: return .none
        }
    }
}
