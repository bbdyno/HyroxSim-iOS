import Foundation
import SwiftData

/// SwiftData entity for persisting segment records within a workout.
/// `measurementsData` stores `SegmentMeasurements` as a JSON blob.
/// If sample counts become very large, consider splitting into a separate entity.
@Model
public final class StoredSegment {
    @Attribute(.unique) public var id: UUID
    /// Corresponds to `WorkoutSegment.id` in the template
    public var segmentId: UUID
    /// Index within the template's segments array (used for ordering)
    public var index: Int
    /// `SegmentType.rawValue`
    public var typeRaw: String
    public var startedAt: Date
    public var endedAt: Date
    public var pausedDuration: TimeInterval

    /// `SegmentMeasurements` serialized as JSON Data
    public var measurementsData: Data

    public var workout: StoredWorkout?

    public init(
        id: UUID,
        segmentId: UUID,
        index: Int,
        typeRaw: String,
        startedAt: Date,
        endedAt: Date,
        pausedDuration: TimeInterval,
        measurementsData: Data,
        workout: StoredWorkout? = nil
    ) {
        self.id = id
        self.segmentId = segmentId
        self.index = index
        self.typeRaw = typeRaw
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedDuration = pausedDuration
        self.measurementsData = measurementsData
        self.workout = workout
    }
}
