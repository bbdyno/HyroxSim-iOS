//
//  WorkoutTemplateMapper.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import HyroxCore

/// Converts between `WorkoutTemplate` (domain) and `StoredTemplate` (SwiftData).
/// Only custom (user-created) templates are persisted. Built-in presets live in code.
public enum WorkoutTemplateMapper {

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Converts a domain `WorkoutTemplate` to a `StoredTemplate` for persistence.
    public static func toStored(_ template: WorkoutTemplate) throws -> StoredTemplate {
        guard let segmentsData = try? encoder.encode(template.segments) else {
            throw PersistenceError.encodingFailed
        }

        return StoredTemplate(
            id: template.id,
            name: template.name,
            divisionRaw: template.division?.rawValue,
            createdAt: template.createdAt,
            segmentsData: segmentsData,
            usesRoxZone: template.usesRoxZone
        )
    }

    /// Converts a `StoredTemplate` back to a domain `WorkoutTemplate`.
    public static func toDomain(_ stored: StoredTemplate) throws -> WorkoutTemplate {
        guard let segments = try? decoder.decode([WorkoutSegment].self, from: stored.segmentsData) else {
            throw PersistenceError.decodingFailed
        }

        let division: HyroxDivision? = stored.divisionRaw.flatMap { HyroxDivision(rawValue: $0) }

        return WorkoutTemplate(
            id: stored.id,
            name: stored.name,
            division: division,
            segments: segments,
            usesRoxZone: stored.usesRoxZone ?? inferredUsesRoxZone(from: segments),
            createdAt: stored.createdAt,
            isBuiltIn: false // Only custom templates are stored
        )
    }

    // MARK: - Legacy rows

    /// Recovers `usesRoxZone` for rows saved before the attribute existed.
    ///
    /// ROX Zones are only ever materialized on a run↔station boundary, so:
    /// - any ROX segment present → the flag was ON
    /// - no ROX segment but a run↔station boundary exists → the user turned it OFF
    /// - no boundary at all (run-only / station-only template) → ON, the default,
    ///   because both settings produce the exact same segment list there.
    static func inferredUsesRoxZone(from segments: [WorkoutSegment]) -> Bool {
        if segments.contains(where: { $0.type == .roxZone }) { return true }
        return !hasRunStationBoundary(segments)
    }

    private static func hasRunStationBoundary(_ segments: [WorkoutSegment]) -> Bool {
        guard segments.count > 1 else { return false }
        for index in 0..<(segments.count - 1) {
            switch (segments[index].type, segments[index + 1].type) {
            case (.run, .station), (.station, .run):
                return true
            default:
                continue
            }
        }
        return false
    }
}
