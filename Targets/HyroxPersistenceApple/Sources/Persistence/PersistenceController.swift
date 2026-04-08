//
//  PersistenceController.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import HyroxCore
import SwiftData

/// Single entry point for persisting workouts and custom templates.
/// Uses SwiftData with local storage (no iCloud sync in this version).
@MainActor
public final class PersistenceController {

    public let container: ModelContainer

    /// Creates a persistence controller.
    /// - Parameter inMemory: If true, uses in-memory storage (for testing).
    public init(inMemory: Bool = false) throws {
        let schema = Schema([StoredWorkout.self, StoredSegment.self, StoredTemplate.self])
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
    public func deleteCompletedWorkout(id: UUID) throws {
        let targetId = id
        let predicate = #Predicate<StoredWorkout> { $0.id == targetId }
        var descriptor = FetchDescriptor<StoredWorkout>(predicate: predicate)
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        guard let stored = results.first else {
            throw PersistenceError.notFound(id: id)
        }
        context.delete(stored)
        try context.save()
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
    public func upsertCompletedWorkout(_ workout: CompletedWorkout) throws {
        let targetId = workout.id
        let predicate = #Predicate<StoredWorkout> { $0.id == targetId }
        var descriptor = FetchDescriptor<StoredWorkout>(predicate: predicate)
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor)
        if let old = existing.first {
            context.delete(old)
        }
        let stored = try CompletedWorkoutMapper.toStored(workout)
        context.insert(stored)
        try context.save()
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
