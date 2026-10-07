//
//  StoredWorkoutTombstone.swift
//  HyroxPersistenceApple
//
//  Created by bbdyno on 9/18/26.
//

import Foundation
import SwiftData

/// Deletion marker for a completed workout.
///
/// Sync is "send everything I have" on both sides, so a record deleted on one
/// device used to be resurrected by the counterpart's next upsert. A tombstone
/// remembers that the user deleted the workout, so:
/// - incoming upserts for that ID are refused (`PersistenceController.upsertCompletedWorkout`)
/// - the ID is excluded from the bulk re-send on session activation
///
/// Rows are tiny (UUID + Date) and are intentionally kept forever; call
/// `PersistenceController.pruneCompletedWorkoutTombstones(before:)` if they ever
/// need trimming. Pruning a tombstone re-opens the door for that ID to come back
/// from a device that has been offline since the deletion.
@Model
public final class StoredWorkoutTombstone {
    /// `CompletedWorkout.id` of the deleted workout.
    @Attribute(.unique) public var workoutId: UUID
    /// When the deletion happened (remote deletions use the sync envelope's timestamp).
    public var deletedAt: Date

    public init(workoutId: UUID, deletedAt: Date) {
        self.workoutId = workoutId
        self.deletedAt = deletedAt
    }
}
