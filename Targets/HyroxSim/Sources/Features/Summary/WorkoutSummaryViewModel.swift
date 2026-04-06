//
//  WorkoutSummaryViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxKit

@Observable
@MainActor
public final class WorkoutSummaryViewModel {
    public let workout: CompletedWorkout
    private let maxHeartRate: Int

    public init(workout: CompletedWorkout, maxHeartRate: Int = 190) {
        self.workout = workout
        self.maxHeartRate = maxHeartRate
    }

    // MARK: - Header

    public var totalTimeText: String {
        DurationFormatter.hms(workout.totalDuration)
    }

    public var titleText: String {
        workout.division?.displayName ?? workout.templateName
    }

    public var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: workout.finishedAt)
    }

    // MARK: - Summary Metrics

    public var distanceText: String {
        DistanceFormatter.short(workout.totalDistanceMeters)
    }

    public var averagePaceText: String {
        DurationFormatter.pace(workout.averageRunPaceSecondsPerKm)
    }

    public var averageHeartRateText: String {
        workout.averageHeartRate.map(String.init) ?? "—"
    }

    public var maxHeartRateText: String {
        workout.maxHeartRate.map(String.init) ?? "—"
    }

    /// Total time spent in all run segments
    public var totalRunTimeText: String {
        let total = workout.runSegments.reduce(0.0) { $0 + $1.activeDuration }
        return DurationFormatter.hms(total)
    }

    /// Total time spent in all ROX Zone segments
    public var totalRoxZoneTimeText: String {
        let total = workout.roxZoneSegments.reduce(0.0) { $0 + $1.activeDuration }
        return DurationFormatter.hms(total)
    }

    // MARK: - Run Paces

    public struct RunPaceItem: Hashable {
        public let index: Int
        public let secondsPerKm: Double?
        public let durationText: String
    }

    public var runPaces: [RunPaceItem] {
        workout.runSegments.enumerated().map { (i, record) in
            RunPaceItem(
                index: i + 1,
                secondsPerKm: record.averagePaceSecondsPerKm,
                durationText: DurationFormatter.ms(record.activeDuration)
            )
        }
    }

    // MARK: - Station Times

    public struct StationItem: Hashable {
        public let index: Int
        public let name: String
        public let durationText: String
        public let durationSeconds: TimeInterval
    }

    public var stationItems: [StationItem] {
        workout.stationSegments.enumerated().map { (i, record) in
            StationItem(
                index: i + 1,
                name: record.stationDisplayName ?? "Station",
                durationText: DurationFormatter.ms(record.activeDuration),
                durationSeconds: record.activeDuration
            )
        }
    }

    // MARK: - Heart Rate Zones

    public struct ZoneItem: Hashable {
        public let zone: HeartRateZone
        public let durationSeconds: TimeInterval
        public let durationText: String
        public let ratio: Double
    }

    /// HR zone distribution based on sample count ratio (approximate).
    /// For higher accuracy, use time-weighted intervals between samples.
    public var heartRateZoneDistribution: [ZoneItem] {
        var counts: [HeartRateZone: Int] = [:]
        var total = 0
        for segment in workout.segments {
            for sample in segment.measurements.heartRateSamples {
                let zone = HeartRateZone.zone(forHeartRate: sample.bpm, maxHeartRate: maxHeartRate)
                counts[zone, default: 0] += 1
                total += 1
            }
        }
        guard total > 0 else { return [] }
        let activeDuration = workout.totalActiveDuration
        return HeartRateZone.allCases.map { zone in
            let ratio = Double(counts[zone] ?? 0) / Double(total)
            let seconds = activeDuration * ratio
            return ZoneItem(zone: zone, durationSeconds: seconds, durationText: DurationFormatter.ms(seconds), ratio: ratio)
        }
    }

    // MARK: - Segment Breakdown

    public enum AccentKind: Hashable { case run, roxZone, station }

    public struct BreakdownItem: Hashable {
        public let index: Int
        public let title: String
        public let detail: String?
        public let durationText: String
        public let accent: AccentKind
    }

    public var breakdownItems: [BreakdownItem] {
        workout.segments.enumerated().map { (i, record) in
            let title: String
            let detail: String?
            let accent: AccentKind
            switch record.type {
            case .run:
                title = "RUN"
                detail = DistanceFormatter.short(record.distanceMeters)
                accent = .run
            case .roxZone:
                title = "ROX ZONE"
                detail = nil
                accent = .roxZone
            case .station:
                title = record.stationDisplayName ?? "Station"
                detail = nil
                accent = .station
            }
            return BreakdownItem(index: i + 1, title: title, detail: detail, durationText: DurationFormatter.ms(record.activeDuration), accent: accent)
        }
    }

    // MARK: - Share Text

    public var shareText: String {
        """
        HYROX \(titleText)
        Total: \(totalTimeText)
        Distance: \(distanceText)
        Avg Pace: \(averagePaceText)
        """
    }
}
