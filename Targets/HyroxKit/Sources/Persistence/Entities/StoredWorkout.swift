import Foundation
import SwiftData

/// SwiftData entity for persisting completed workouts.
/// Domain ↔ Stored conversion is handled by `CompletedWorkoutMapper`.
@Model
public final class StoredWorkout {
    @Attribute(.unique) public var id: UUID
    public var templateName: String
    /// `HyroxDivision.rawValue` or nil for custom workouts
    public var divisionRaw: String?
    public var startedAt: Date
    public var finishedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoredSegment.workout)
    public var segments: [StoredSegment]

    public init(
        id: UUID,
        templateName: String,
        divisionRaw: String?,
        startedAt: Date,
        finishedAt: Date,
        segments: [StoredSegment] = []
    ) {
        self.id = id
        self.templateName = templateName
        self.divisionRaw = divisionRaw
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.segments = segments
    }
}
