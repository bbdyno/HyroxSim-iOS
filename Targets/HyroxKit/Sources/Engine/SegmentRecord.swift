import Foundation

/// Result produced when a segment is completed by the engine.
/// Contains timing data and raw measurements (GPS + heart rate).
public struct SegmentRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Corresponds to `WorkoutSegment.id` in the template
    public let segmentId: UUID
    /// Index within the template's segments array
    public let index: Int
    public let type: SegmentType
    public let startedAt: Date
    public let endedAt: Date
    /// Time spent paused during this segment
    public let pausedDuration: TimeInterval
    /// Raw measurement data collected during this segment
    public var measurements: SegmentMeasurements

    /// Total wall-clock duration (includes paused time)
    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    /// Actual active exercise duration (excludes paused time)
    public var activeDuration: TimeInterval { duration - pausedDuration }

    // MARK: - Derived (convenience)

    /// Cumulative GPS distance in meters
    public var distanceMeters: Double { measurements.distanceMeters }
    /// Average pace in sec/km based on active duration
    public var averagePaceSecondsPerKm: Double? {
        measurements.averagePaceSecondsPerKm(activeDuration: activeDuration)
    }
    /// Average heart rate for this segment
    public var averageHeartRate: Int? { measurements.averageHeartRate }

    public init(
        id: UUID = UUID(),
        segmentId: UUID,
        index: Int,
        type: SegmentType,
        startedAt: Date,
        endedAt: Date,
        pausedDuration: TimeInterval = 0,
        measurements: SegmentMeasurements = SegmentMeasurements()
    ) {
        self.id = id
        self.segmentId = segmentId
        self.index = index
        self.type = type
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedDuration = pausedDuration
        self.measurements = measurements
    }
}
