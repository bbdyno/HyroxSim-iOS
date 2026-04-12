//
//  WorkoutBuilderViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxCore
import HyroxPersistenceApple

@Observable
@MainActor
public final class WorkoutBuilderViewModel {
    public private(set) var name: String
    public private(set) var division: HyroxDivision?
    public private(set) var segments: [WorkoutSegment]
    public private(set) var usesRoxZone: Bool

    private let persistence: PersistenceController

    public init(startingFrom template: WorkoutTemplate?, persistence: PersistenceController) {
        self.persistence = persistence
        if let t = template {
            self.name = t.isBuiltIn ? "Custom from \(t.name)" : t.name
            self.division = t.division
            self.usesRoxZone = t.usesRoxZone || t.segments.contains(where: { $0.type == .roxZone })
            // Builder only edits logical segments. ROX Zone is synthesized from the toggle.
            self.segments = t.logicalSegments
                .map { seg in
                WorkoutSegment(
                    type: seg.type,
                    distanceMeters: seg.distanceMeters,
                    goalDurationSeconds: seg.goalDurationSeconds,
                    stationKind: seg.stationKind,
                    stationTarget: seg.stationTarget,
                    weightKg: seg.weightKg,
                    weightNote: seg.weightNote
                )
            }
        } else {
            self.name = "My Workout"
            self.division = nil
            self.segments = []
            self.usesRoxZone = true
        }
    }

    // MARK: - Editing

    public func rename(to newName: String) { name = newName }

    public func setUsesRoxZone(_ enabled: Bool) {
        usesRoxZone = enabled
    }

    public func addSegment(_ segment: WorkoutSegment, at index: Int? = nil) {
        if let i = index { segments.insert(segment, at: i) } else { segments.append(segment) }
    }

    public func removeSegment(at index: Int) {
        guard index < segments.count else { return }
        segments.remove(at: index)
    }

    public func moveSegment(from source: Int, to destination: Int) {
        guard source < segments.count, destination <= segments.count else { return }
        let s = segments.remove(at: source)
        segments.insert(s, at: min(destination, segments.count))
    }

    public func updateSegment(at index: Int, _ updated: WorkoutSegment) {
        guard index < segments.count else { return }
        segments[index] = updated
    }

    // MARK: - Derived

    public var isEmpty: Bool { segments.isEmpty }

    public var canSave: Bool {
        !segments.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var canStart: Bool { !segments.isEmpty }

    public var totalRunDistanceMeters: Double {
        segments.filter { $0.type == .run }.compactMap(\.distanceMeters).reduce(0, +)
    }

    public var stationCount: Int {
        segments.filter { $0.type == .station }.count
    }

    public var estimatedDurationSeconds: TimeInterval {
        materializedSegments().reduce(0) { total, seg in
            total + (seg.goalDurationSeconds ?? WorkoutSegment.defaultGoalDurationSeconds(
                for: seg.type,
                distanceMeters: seg.distanceMeters
            ))
        }
    }

    // MARK: - Persist

    public func saveAsTemplate() throws -> WorkoutTemplate {
        let template = WorkoutTemplate(
            name: name,
            division: division,
            segments: materializedSegments(),
            usesRoxZone: usesRoxZone,
            isBuiltIn: false
        )
        try template.validate()
        try persistence.saveTemplate(template)
        return template
    }

    public func makeTemplateForStart() throws -> WorkoutTemplate {
        let template = WorkoutTemplate(
            name: name,
            division: division,
            segments: materializedSegments(),
            usesRoxZone: usesRoxZone,
            isBuiltIn: false
        )
        try template.validate()
        return template
    }

    private func materializedSegments() -> [WorkoutSegment] {
        WorkoutTemplate.materializedSegments(from: segments, usesRoxZone: usesRoxZone)
    }
}
