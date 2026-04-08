//
//  CompletedWorkout.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Final result container for a completed workout.
/// Created from `WorkoutEngine.makeCompletedWorkout()` after the workout finishes.
public struct CompletedWorkout: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let templateName: String
    public let division: HyroxDivision?
    public let startedAt: Date
    public let finishedAt: Date
    public let segments: [SegmentRecord]

    public init(
        id: UUID = UUID(),
        templateName: String,
        division: HyroxDivision? = nil,
        startedAt: Date,
        finishedAt: Date,
        segments: [SegmentRecord]
    ) {
        self.id = id
        self.templateName = templateName
        self.division = division
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.segments = segments
    }

    // MARK: - Derived

    /// Total wall-clock duration from start to finish
    public var totalDuration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    /// Sum of all segments' active durations (excluding paused time)
    public var totalActiveDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.activeDuration }
    }

    /// Total distance across all segments in meters
    public var totalDistanceMeters: Double {
        segments.reduce(0) { $0 + $1.distanceMeters }
    }

    /// All run segments
    public var runSegments: [SegmentRecord] {
        segments.filter { $0.type == .run }
    }

    /// All ROX Zone segments
    public var roxZoneSegments: [SegmentRecord] {
        segments.filter { $0.type == .roxZone }
    }

    /// All station segments
    public var stationSegments: [SegmentRecord] {
        segments.filter { $0.type == .station }
    }

    /// Average heart rate across all segments that have HR data. Nil if none.
    public var averageHeartRate: Int? {
        let allSamples = segments.flatMap(\.measurements.heartRateSamples)
        guard !allSamples.isEmpty else { return nil }
        let sum = allSamples.reduce(0) { $0 + $1.bpm }
        return sum / allSamples.count
    }

    /// Maximum heart rate across the entire workout. Nil if no HR data.
    public var maxHeartRate: Int? {
        segments.compactMap(\.measurements.maxHeartRate).max()
    }

    /// Average run pace in seconds per kilometer (run + roxZone segments only).
    /// Nil if total run distance is effectively zero.
    public var averageRunPaceSecondsPerKm: Double? {
        let runAndRox = segments.filter { $0.type == .run || $0.type == .roxZone }
        let totalDist = runAndRox.reduce(0.0) { $0 + $1.distanceMeters }
        let totalActive = runAndRox.reduce(0.0) { $0 + $1.activeDuration }
        let km = totalDist / 1000.0
        guard km > 0.001 else { return nil }
        return totalActive / km
    }

    /// Resolves a station label for display. Old persisted workouts may be
    /// missing `stationDisplayName`, so standard HYROX divisions fall back to
    /// the official station order.
    public func resolvedStationDisplayName(for record: SegmentRecord) -> String? {
        guard record.type == .station else { return nil }
        if let stationDisplayName = record.stationDisplayName, !stationDisplayName.isEmpty {
            return stationDisplayName
        }
        guard let division, let stationOrdinal = stationOrdinal(for: record) else { return nil }
        let stations = HyroxDivisionSpec.stations(for: division)
        guard stations.indices.contains(stationOrdinal) else { return nil }
        return stations[stationOrdinal].kind.displayName
    }

    private func stationOrdinal(for record: SegmentRecord) -> Int? {
        var stationOrdinal = 0
        for segment in segments {
            guard segment.type == .station else { continue }
            let isSameRecord =
                segment.id == record.id ||
                (segment.segmentId == record.segmentId && segment.index == record.index) ||
                segment.index == record.index
            if isSameRecord {
                return stationOrdinal
            }
            stationOrdinal += 1
        }
        return nil
    }
}
