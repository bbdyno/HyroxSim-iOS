//
//  WorkoutTemplateMapper.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

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
            segmentsData: segmentsData
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
            createdAt: stored.createdAt,
            isBuiltIn: false // Only custom templates are stored
        )
    }
}
