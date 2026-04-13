//
//  WorkoutSummaryViewModel.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import Foundation
import Observation
import HyroxCore

@Observable
@MainActor
public final class WorkoutSummaryViewModel {
    public let workout: CompletedWorkout
    private let maxHeartRate: Int

    public init(workout: CompletedWorkout, maxHeartRate: Int = 190) {
        self.workout = workout
        self.maxHeartRate = maxHeartRate
    }

    public enum DeltaTone: Hashable {
        case ahead
        case behind
        case neutral
    }

    public struct GoalDelta: Hashable {
        public let text: String
        public let tone: DeltaTone
        public let seconds: TimeInterval?
    }

    public struct DetailItem: Hashable, Identifiable {
        public enum Accent: Hashable {
            case run
            case roxZone
            case station
        }

        public let id: UUID
        public let title: String
        public let subtitle: String?
        public let durationText: String
        public let delta: GoalDelta
        public let accent: Accent
    }

    public struct RunGroupItem: Hashable, Identifiable {
        public let id: String
        public let index: Int
        public let title: String
        public let subtitle: String?
        public let durationText: String
        public let delta: GoalDelta
        public let detailItems: [DetailItem]
    }

    public struct SectionStationItem: Hashable, Identifiable {
        public let id: UUID
        public let index: Int
        public let title: String
        public let subtitle: String?
        public let durationText: String
        public let delta: GoalDelta
    }

    public struct RoundSection: Hashable, Identifiable {
        public let id: String
        public let runGroup: RunGroupItem?
        public let station: SectionStationItem?
    }

    public struct HeaderMetric: Hashable {
        public let title: String
        public let value: String
    }

    public struct RunPaceItem: Hashable {
        public let index: Int
        public let secondsPerKm: Double?
        public let durationText: String
    }

    public struct StationItem: Hashable {
        public let index: Int
        public let name: String
        public let durationText: String
        public let durationSeconds: TimeInterval
    }

    public struct ZoneItem: Hashable {
        public let zone: HeartRateZone
        public let durationSeconds: TimeInterval
        public let durationText: String
        public let ratio: Double
    }

    public enum AccentKind: Hashable {
        case run
        case roxZone
        case station
    }

    public struct BreakdownItem: Hashable {
        public let index: Int
        public let title: String
        public let detail: String?
        public let durationText: String
        public let accent: AccentKind
    }

    public var titleText: String {
        workout.division?.displayName ?? workout.templateName
    }

    public var dateText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: workout.finishedAt)
    }

    public var totalTimeText: String {
        DurationFormatter.hms(workout.totalDuration)
    }

    public var totalGoalText: String {
        guard let totalGoalSeconds else { return "—" }
        return DurationFormatter.hms(totalGoalSeconds)
    }

    public var totalDelta: GoalDelta {
        guard let totalGoalSeconds else {
            return GoalDelta(text: "—", tone: .neutral, seconds: nil)
        }
        return goalDelta(actual: workout.totalDuration, goal: totalGoalSeconds)
    }

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

    public var totalRunTimeText: String {
        let total = workout.runSegments.reduce(0) { $0 + $1.activeDuration }
        return DurationFormatter.hms(total)
    }

    public var totalRoxZoneTimeText: String {
        let total = workout.roxZoneSegments.reduce(0) { $0 + $1.activeDuration }
        return DurationFormatter.hms(total)
    }

    public var headerMetrics: [HeaderMetric] {
        [
            HeaderMetric(title: "DIST", value: distanceText),
            HeaderMetric(title: "PACE", value: averagePaceText),
            HeaderMetric(title: "AVG HR", value: averageHeartRateText),
            HeaderMetric(title: "MAX HR", value: maxHeartRateText)
        ]
    }

    public var sections: [RoundSection] {
        var result: [RoundSection] = []
        var runGroupIndex = 0
        var stationIndex = 0
        var cursor = 0
        var leadingRoxRecords: [SegmentRecord] = []

        while cursor < workout.segments.count {
            var runRecords: [SegmentRecord] = leadingRoxRecords
            leadingRoxRecords = []

            while cursor < workout.segments.count {
                let record = workout.segments[cursor]
                guard record.type != .station else { break }
                runRecords.append(record)
                cursor += 1
            }

            let runGroup: RunGroupItem?
            if runRecords.isEmpty {
                runGroup = nil
            } else {
                runGroupIndex += 1
                runGroup = makeRunGroup(index: runGroupIndex, records: runRecords)
            }

            let station: SectionStationItem?
            if cursor < workout.segments.count, workout.segments[cursor].type == .station {
                stationIndex += 1
                let stationRecord = workout.segments[cursor]
                cursor += 1

                while cursor < workout.segments.count, workout.segments[cursor].type == .roxZone {
                    leadingRoxRecords.append(workout.segments[cursor])
                    cursor += 1
                }

                station = makeStationItem(index: stationIndex, record: stationRecord)
            } else {
                station = nil
            }

            guard runGroup != nil || station != nil else { break }
            let id = station.map { "round-\($0.index)" } ?? "round-tail-\(runGroupIndex)"
            result.append(
                RoundSection(
                    id: id,
                    runGroup: runGroup,
                    station: station
                )
            )
        }

        return result
    }

    public var runPaces: [RunPaceItem] {
        workout.runSegments.enumerated().map { index, record in
            RunPaceItem(
                index: index + 1,
                secondsPerKm: record.averagePaceSecondsPerKm,
                durationText: DurationFormatter.ms(record.activeDuration)
            )
        }
    }

    public var stationItems: [StationItem] {
        workout.stationSegments.enumerated().map { index, record in
            StationItem(
                index: index + 1,
                name: workout.resolvedStationDisplayName(for: record) ?? "Station \(index + 1)",
                durationText: DurationFormatter.ms(record.activeDuration),
                durationSeconds: record.activeDuration
            )
        }
    }

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
            return ZoneItem(
                zone: zone,
                durationSeconds: seconds,
                durationText: DurationFormatter.ms(seconds),
                ratio: ratio
            )
        }
    }

    public var breakdownItems: [BreakdownItem] {
        workout.segments.enumerated().map { index, record in
            let title: String
            let detail: String?
            let accent: AccentKind

            switch record.type {
            case .run:
                title = "RUN"
                detail = DistanceFormatter.short(record.plannedDistanceMeters ?? record.distanceMeters)
                accent = .run

            case .roxZone:
                title = "ROX ZONE"
                detail = nil
                accent = .roxZone

            case .station:
                title = workout.resolvedStationDisplayName(for: record) ?? "Station"
                detail = nil
                accent = .station
            }

            return BreakdownItem(
                index: index + 1,
                title: title,
                detail: detail,
                durationText: DurationFormatter.ms(record.activeDuration),
                accent: accent
            )
        }
    }

    public var shareText: String {
        var lines = [
            "HYROX \(titleText)",
            "Total: \(totalTimeText)",
            "Goal: \(totalGoalText)",
            "Delta: \(totalDelta.text)",
            "Distance: \(distanceText)",
            "Avg Pace: \(averagePaceText)"
        ]

        for section in sections {
            if let runGroup = section.runGroup {
                lines.append("\(runGroup.title): \(runGroup.durationText) (\(runGroup.delta.text))")
            }
            if let station = section.station {
                lines.append("\(station.title): \(station.durationText) (\(station.delta.text))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private var totalGoalSeconds: TimeInterval? {
        let goals = workout.segments.compactMap(\.goalDurationSeconds)
        guard !goals.isEmpty else { return nil }
        return goals.reduce(0, +)
    }

    private func makeRunGroup(index: Int, records: [SegmentRecord]) -> RunGroupItem {
        let combinedDuration = records.reduce(0) { $0 + $1.activeDuration }
        let combinedGoal = records.compactMap(\.goalDurationSeconds).reduce(0, +)
        let delta = combinedGoal > 0
            ? goalDelta(actual: combinedDuration, goal: combinedGoal)
            : GoalDelta(text: "—", tone: .neutral, seconds: nil)

        let detailItems = records.compactMap { record in
            switch record.type {
            case .run:
                return DetailItem(
                    id: record.id,
                    title: "Run \(index)",
                    subtitle: DistanceFormatter.short(record.plannedDistanceMeters ?? record.distanceMeters),
                    durationText: DurationFormatter.hms(record.activeDuration),
                    delta: goalDelta(actual: record.activeDuration, goal: record.goalDurationSeconds),
                    accent: .run
                )

            case .roxZone:
                return DetailItem(
                    id: record.id,
                    title: "Rox Zone",
                    subtitle: "Transition",
                    durationText: DurationFormatter.hms(record.activeDuration),
                    delta: goalDelta(actual: record.activeDuration, goal: record.goalDurationSeconds),
                    accent: .roxZone
                )

            case .station:
                return nil
            }
        }

        let hasRox = records.contains { $0.type == .roxZone }
        return RunGroupItem(
            id: "run-group-\(index)",
            index: index,
            title: hasRox ? "RUN \(index) + ROX" : "RUN \(index)",
            subtitle: nil,
            durationText: DurationFormatter.hms(combinedDuration),
            delta: delta,
            detailItems: detailItems
        )
    }

    private func makeStationItem(index: Int, record: SegmentRecord) -> SectionStationItem {
        let resolvedName = workout.resolvedStationDisplayName(for: record) ?? "Station \(index)"
        let rawName = record.stationDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = (rawName?.isEmpty == false && rawName != resolvedName) ? rawName : nil

        return SectionStationItem(
            id: record.id,
            index: index,
            title: resolvedName,
            subtitle: subtitle,
            durationText: DurationFormatter.hms(record.activeDuration),
            delta: goalDelta(actual: record.activeDuration, goal: record.goalDurationSeconds)
        )
    }

    private func goalDelta(actual: TimeInterval, goal: TimeInterval?) -> GoalDelta {
        guard let goal, goal > 0 else {
            return GoalDelta(text: "—", tone: .neutral, seconds: nil)
        }

        let delta = actual - goal
        let tone: DeltaTone
        if delta < 0 {
            tone = .ahead
        } else if delta > 0 {
            tone = .behind
        } else {
            tone = .neutral
        }

        return GoalDelta(
            text: DurationFormatter.signedMs(delta),
            tone: tone,
            seconds: delta
        )
    }
}
