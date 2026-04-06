import Foundation

/// A single segment in a workout template
public struct WorkoutSegment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var type: SegmentType

    /// Distance in meters (meaningful for run/roxZone segments)
    public var distanceMeters: Double?

    /// Kind of station exercise (meaningful for station segments)
    public var stationKind: StationKind?
    /// Target for the station exercise
    public var stationTarget: StationTarget?
    /// Weight in kilograms
    public var weightKg: Double?
    /// Weight annotation (e.g., "per hand", "sled total")
    public var weightNote: String?

    public init(
        id: UUID = UUID(),
        type: SegmentType,
        distanceMeters: Double? = nil,
        stationKind: StationKind? = nil,
        stationTarget: StationTarget? = nil,
        weightKg: Double? = nil,
        weightNote: String? = nil
    ) {
        self.id = id
        self.type = type
        self.distanceMeters = distanceMeters
        self.stationKind = stationKind
        self.stationTarget = stationTarget
        self.weightKg = weightKg
        self.weightNote = weightNote
    }

    // MARK: - Convenience Constructors

    /// Creates a run segment with the given distance (default 1 km)
    public static func run(distanceMeters: Double = 1000) -> WorkoutSegment {
        WorkoutSegment(type: .run, distanceMeters: distanceMeters)
    }

    /// Creates a ROX Zone transition segment
    public static func roxZone() -> WorkoutSegment {
        WorkoutSegment(type: .roxZone)
    }

    /// Creates a station segment
    public static func station(
        _ kind: StationKind,
        target: StationTarget? = nil,
        weightKg: Double? = nil,
        weightNote: String? = nil
    ) -> WorkoutSegment {
        WorkoutSegment(
            type: .station,
            stationKind: kind,
            stationTarget: target,
            weightKg: weightKg,
            weightNote: weightNote
        )
    }

    // MARK: - Validation

    public enum ValidationError: LocalizedError, Equatable {
        case runSegmentHasStationData
        case stationSegmentHasDistanceData

        public var errorDescription: String? {
            switch self {
            case .runSegmentHasStationData:
                return "Run/RoxZone segment should not have station data (stationKind, weightKg)"
            case .stationSegmentHasDistanceData:
                return "Station segment should not have distanceMeters"
            }
        }
    }

    /// Validates that the segment data is consistent with its type
    public func validate() throws {
        switch type {
        case .run, .roxZone:
            if stationKind != nil || weightKg != nil {
                throw ValidationError.runSegmentHasStationData
            }
        case .station:
            if distanceMeters != nil {
                throw ValidationError.stationSegmentHasDistanceData
            }
        }
    }
}
