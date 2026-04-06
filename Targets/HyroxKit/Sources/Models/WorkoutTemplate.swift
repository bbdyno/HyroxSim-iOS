import Foundation

/// A reusable workout template defining the structure of a workout
public struct WorkoutTemplate: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// The HYROX division this template is for (nil for custom templates)
    public var division: HyroxDivision?
    public var segments: [WorkoutSegment]
    public var createdAt: Date
    /// Whether this is a built-in preset template
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        division: HyroxDivision? = nil,
        segments: [WorkoutSegment],
        createdAt: Date = Date(),
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.division = division
        self.segments = segments
        self.createdAt = createdAt
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - Computed Properties

    /// Total distance of all run segments in meters
    public var totalRunDistanceMeters: Double {
        segments
            .filter { $0.type == .run }
            .compactMap(\.distanceMeters)
            .reduce(0, +)
    }

    /// Number of station segments
    public var stationCount: Int {
        segments.filter { $0.type == .station }.count
    }

    /// Estimated total duration in seconds (rough estimate for display)
    public var estimatedDurationSeconds: TimeInterval {
        segments.reduce(0) { total, segment in
            switch segment.type {
            case .run:
                let distance = segment.distanceMeters ?? 1000
                return total + distance * 0.36 // ~6 min per 1000 m
            case .roxZone:
                return total + 30
            case .station:
                return total + 240 // ~4 min per station
            }
        }
    }

    // MARK: - Validation

    public enum ValidationError: LocalizedError, Equatable {
        case emptySegments

        public var errorDescription: String? {
            switch self {
            case .emptySegments:
                return "Workout template must have at least one segment"
            }
        }
    }

    /// Validates the template structure and all contained segments
    public func validate() throws {
        if segments.isEmpty {
            throw ValidationError.emptySegments
        }
        for segment in segments {
            try segment.validate()
        }
    }
}
