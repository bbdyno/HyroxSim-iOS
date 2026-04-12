//
//  CompletedWorkoutMapper.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import HyroxCore

/// Converts between `CompletedWorkout` (domain) and `StoredWorkout` (SwiftData).
public enum CompletedWorkoutMapper {

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Converts a domain `CompletedWorkout` to a `StoredWorkout` for persistence.
    public static func toStored(_ workout: CompletedWorkout) throws -> StoredWorkout {
        let storedSegments = try workout.segments.map { record -> StoredSegment in
            guard let measData = try? encoder.encode(record.measurements) else {
                throw PersistenceError.encodingFailed
            }
            return StoredSegment(
                id: record.id,
                segmentId: record.segmentId,
                index: record.index,
                typeRaw: record.type.rawValue,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                pausedDuration: record.pausedDuration,
                stationDisplayName: record.stationDisplayName,
                plannedDistanceMeters: record.plannedDistanceMeters,
                goalDurationSeconds: record.goalDurationSeconds,
                measurementsData: measData
            )
        }

        return StoredWorkout(
            id: workout.id,
            templateName: workout.templateName,
            divisionRaw: workout.division?.rawValue,
            startedAt: workout.startedAt,
            finishedAt: workout.finishedAt,
            segments: storedSegments
        )
    }

    /// Converts a `StoredWorkout` back to a domain `CompletedWorkout`.
    public static func toDomain(_ stored: StoredWorkout) throws -> CompletedWorkout {
        let sortedSegments = stored.segments.sorted { $0.index < $1.index }

        let records = try sortedSegments.map { seg -> SegmentRecord in
            guard let type = SegmentType(rawValue: seg.typeRaw) else {
                throw PersistenceError.decodingFailed
            }
            guard let measurements = try? decoder.decode(SegmentMeasurements.self, from: seg.measurementsData) else {
                throw PersistenceError.decodingFailed
            }
            return SegmentRecord(
                id: seg.id,
                segmentId: seg.segmentId,
                index: seg.index,
                type: type,
                startedAt: seg.startedAt,
                endedAt: seg.endedAt,
                pausedDuration: seg.pausedDuration,
                measurements: measurements,
                stationDisplayName: seg.stationDisplayName,
                plannedDistanceMeters: seg.plannedDistanceMeters,
                goalDurationSeconds: seg.goalDurationSeconds
            )
        }

        let division: HyroxDivision? = stored.divisionRaw.flatMap { HyroxDivision(rawValue: $0) }

        return CompletedWorkout(
            id: stored.id,
            templateName: stored.templateName,
            division: division,
            startedAt: stored.startedAt,
            finishedAt: stored.finishedAt,
            segments: records
        )
    }
}
