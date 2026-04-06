import Foundation

/// Result produced when a segment is completed by the engine.
/// Measurement data (location, heart rate) is not included in this stage —
/// it will be added or combined via a separate model in a later phase.
public struct SegmentRecord: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Corresponds to `WorkoutSegment.id` in the template
    public let segmentId: UUID
    /// Index within the template's segments array
    public let index: Int
    public let type: SegmentType
    public let startedAt: Date
    public let endedAt: Date
    /// Total wall-clock duration (includes paused time)
    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    /// Time spent paused during this segment
    public let pausedDuration: TimeInterval
    /// Actual active exercise duration (excludes paused time)
    public var activeDuration: TimeInterval { duration - pausedDuration }

    public init(
        id: UUID = UUID(),
        segmentId: UUID,
        index: Int,
        type: SegmentType,
        startedAt: Date,
        endedAt: Date,
        pausedDuration: TimeInterval = 0
    ) {
        self.id = id
        self.segmentId = segmentId
        self.index = index
        self.type = type
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedDuration = pausedDuration
    }
}
