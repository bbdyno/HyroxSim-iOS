//
//  PersistenceController.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import HyroxCore
import SwiftData

extension Notification.Name {
    /// Posted on the main thread right after the user deletes a completed workout
    /// *locally* (`PersistenceController.deleteCompletedWorkout`).
    /// `userInfo[PersistenceController.deletedWorkoutIdKey]` carries the `UUID`.
    ///
    /// Sync coordinators observe this to tell the counterpart device about the
    /// deletion, which keeps history screens free of any sync knowledge.
    /// Deletions that *arrive* from the counterpart deliberately do not post it
    /// (see `applyRemoteCompletedWorkoutDeletion`) so the two devices can't echo
    /// the same deletion back and forth.
    public static let hyroxCompletedWorkoutDeleted = Notification.Name("com.hyroxsim.completedWorkoutDeleted")
}

/// Single entry point for persisting workouts and custom templates.
/// Uses SwiftData with local storage (no iCloud sync in this version).
@MainActor
public final class PersistenceController {

    /// `userInfo` key carrying the deleted workout's `UUID` in
    /// `Notification.Name.hyroxCompletedWorkoutDeleted`.
    /// `nonisolated` so notification observers can read it off the main actor.
    nonisolated public static let deletedWorkoutIdKey = "id"

    public let container: ModelContainer

    /// Creates a persistence controller.
    /// - Parameter inMemory: If true, uses in-memory storage (for testing).
    public init(inMemory: Bool = false) throws {
        let schema = Schema([
            StoredWorkout.self,
            StoredSegment.self,
            StoredTemplate.self,
            StoredWorkoutTombstone.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    private var context: ModelContext { container.mainContext }

    // MARK: - CompletedWorkout

    /// Saves a completed workout to persistent storage.
    public func saveCompletedWorkout(_ workout: CompletedWorkout) throws {
        let stored = try CompletedWorkoutMapper.toStored(workout)
        context.insert(stored)
        try context.save()
    }

    /// Fetches all completed workouts, most recent first.
    public func fetchAllCompletedWorkouts() throws -> [CompletedWorkout] {
        let descriptor = FetchDescriptor<StoredWorkout>(
            sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]
        )
        let results = try context.fetch(descriptor)
        return try results.map { try CompletedWorkoutMapper.toDomain($0) }
    }

    /// Fetches a single completed workout by ID.
    public func fetchCompletedWorkout(id: UUID) throws -> CompletedWorkout {
        let targetId = id
        let predicate = #Predicate<StoredWorkout> { $0.id == targetId }
        var descriptor = FetchDescriptor<StoredWorkout>(predicate: predicate)
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        guard let stored = results.first else {
            throw PersistenceError.notFound(id: id)
        }
        return try CompletedWorkoutMapper.toDomain(stored)
    }

    /// Deletes a completed workout and its segments (cascade).
    ///
    /// Also writes a tombstone so the counterpart device can't push the record
    /// back, and posts `.hyroxCompletedWorkoutDeleted` so sync coordinators can
    /// forward the deletion.
    public func deleteCompletedWorkout(id: UUID) throws {
        guard let stored = try storedWorkout(id: id) else {
            throw PersistenceError.notFound(id: id)
        }
        // Tombstone first: its lookup runs before any pending deletion.
        insertTombstoneIfNeeded(id: id, deletedAt: Date())
        context.delete(stored)
        try context.save()

        NotificationCenter.default.post(
            name: .hyroxCompletedWorkoutDeleted,
            object: nil,
            userInfo: [Self.deletedWorkoutIdKey: id]
        )
    }

    // MARK: - Deletion Tombstones

    /// Records that a workout was deleted, without touching the stored record.
    /// Idempotent — a second call for the same ID keeps the first timestamp.
    /// - Returns: `true` when a new tombstone was written.
    @discardableResult
    public func markCompletedWorkoutDeleted(id: UUID, at date: Date = Date()) throws -> Bool {
        let inserted = insertTombstoneIfNeeded(id: id, deletedAt: date)
        if inserted { try context.save() }
        return inserted
    }

    /// Applies a deletion that originated on the counterpart device: records the
    /// tombstone and removes the local copy, *without* posting
    /// `.hyroxCompletedWorkoutDeleted` (that notification is the outbound trigger,
    /// so re-posting it here would bounce the deletion back to the sender).
    /// - Returns: `true` when a local record was actually removed.
    @discardableResult
    public func applyRemoteCompletedWorkoutDeletion(id: UUID, deletedAt: Date = Date()) throws -> Bool {
        let stored = try storedWorkout(id: id)
        insertTombstoneIfNeeded(id: id, deletedAt: deletedAt)
        if let stored { context.delete(stored) }
        try context.save()
        return stored != nil
    }

    /// Whether the workout was deleted by the user on this device (or on the
    /// counterpart, once its deletion message arrived).
    public func isCompletedWorkoutDeleted(id: UUID) -> Bool {
        // `try?` flattens the optional result: nil means "no tombstone or fetch failed".
        (try? tombstone(id: id)) != nil
    }

    /// All tombstoned workout IDs — used to keep deleted records out of the bulk
    /// re-send that runs on every WatchConnectivity activation.
    public func deletedCompletedWorkoutIds() -> Set<UUID> {
        let descriptor = FetchDescriptor<StoredWorkoutTombstone>()
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return Set(rows.map(\.workoutId))
    }

    /// Drops tombstones older than `date`. Not called automatically: a pruned ID
    /// can be resurrected by a device that has been offline since the deletion.
    @discardableResult
    public func pruneCompletedWorkoutTombstones(before date: Date) throws -> Int {
        let cutoff = date
        let predicate = #Predicate<StoredWorkoutTombstone> { $0.deletedAt < cutoff }
        let stale = try context.fetch(FetchDescriptor<StoredWorkoutTombstone>(predicate: predicate))
        guard !stale.isEmpty else { return 0 }
        stale.forEach { context.delete($0) }
        try context.save()
        return stale.count
    }

    private func storedWorkout(id: UUID) throws -> StoredWorkout? {
        let targetId = id
        let predicate = #Predicate<StoredWorkout> { $0.id == targetId }
        var descriptor = FetchDescriptor<StoredWorkout>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func tombstone(id: UUID) throws -> StoredWorkoutTombstone? {
        let targetId = id
        let predicate = #Predicate<StoredWorkoutTombstone> { $0.workoutId == targetId }
        var descriptor = FetchDescriptor<StoredWorkoutTombstone>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Inserts a tombstone when the ID has none yet. Caller saves the context.
    @discardableResult
    private func insertTombstoneIfNeeded(id: UUID, deletedAt: Date) -> Bool {
        guard (try? tombstone(id: id)) == nil else { return false }
        context.insert(StoredWorkoutTombstone(workoutId: id, deletedAt: deletedAt))
        return true
    }

    // MARK: - Custom Templates

    /// Saves a custom workout template.
    public func saveTemplate(_ template: WorkoutTemplate) throws {
        let stored = try WorkoutTemplateMapper.toStored(template)
        context.insert(stored)
        try context.save()
    }

    /// Fetches all custom templates, sorted by creation date (newest first).
    public func fetchAllTemplates() throws -> [WorkoutTemplate] {
        let descriptor = FetchDescriptor<StoredTemplate>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let results = try context.fetch(descriptor)
        return try results.map { try WorkoutTemplateMapper.toDomain($0) }
    }

    /// Fetches a single custom template by ID.
    public func fetchTemplate(id: UUID) throws -> WorkoutTemplate {
        let targetId = id
        let predicate = #Predicate<StoredTemplate> { $0.id == targetId }
        var descriptor = FetchDescriptor<StoredTemplate>(predicate: predicate)
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        guard let stored = results.first else {
            throw PersistenceError.notFound(id: id)
        }
        return try WorkoutTemplateMapper.toDomain(stored)
    }

    /// Deletes a custom template.
    public func deleteTemplate(id: UUID) throws {
        let targetId = id
        let predicate = #Predicate<StoredTemplate> { $0.id == targetId }
        var descriptor = FetchDescriptor<StoredTemplate>(predicate: predicate)
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        guard let stored = results.first else {
            throw PersistenceError.notFound(id: id)
        }
        context.delete(stored)
        try context.save()
    }

    // MARK: - Upsert (Sync)

    /// Inserts or replaces a completed workout by ID. Used for sync receive.
    ///
    /// Refuses records the user already deleted (tombstoned) — the counterpart
    /// re-sends its whole history on every activation, which used to resurrect
    /// them on the next launch.
    /// - Returns: `false` when the upsert was skipped because of a tombstone.
    @discardableResult
    public func upsertCompletedWorkout(_ workout: CompletedWorkout) throws -> Bool {
        guard !isCompletedWorkoutDeleted(id: workout.id) else { return false }

        if let old = try storedWorkout(id: workout.id) {
            context.delete(old)
        }
        let stored = try CompletedWorkoutMapper.toStored(workout)
        context.insert(stored)
        try context.save()
        return true
    }

    /// Inserts or replaces a template by ID. Used for sync receive.
    public func upsertTemplate(_ template: WorkoutTemplate) throws {
        let targetId = template.id
        let predicate = #Predicate<StoredTemplate> { $0.id == targetId }
        var descriptor = FetchDescriptor<StoredTemplate>(predicate: predicate)
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor)
        if let old = existing.first {
            context.delete(old)
        }
        let stored = try WorkoutTemplateMapper.toStored(template)
        context.insert(stored)
        try context.save()
    }
}
