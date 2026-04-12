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

    public init(workout: CompletedWorkout) {
        self.workout = workout
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

    public struct StationItem: Hashable, Identifiable {
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
        public let station: StationItem?
    }

    public struct HeaderMetric: Hashable {
        public let title: String
        public let value: String
        public let tint: DeltaTone
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
        let goals = workout.segments.compactMap(\.goalDurationSeconds)
        guard !goals.isEmpty else { return "—" }
        return DurationFormatter.hms(goals.reduce(0, +))
    }

    public var totalDelta: GoalDelta {
        let totalGoal = workout.segments.compactMap(\.goalDurationSeconds).reduce(0, +)
        guard totalGoal > 0 else { return GoalDelta(text: "—", tone: .neutral, seconds: nil) }
        return goalDelta(actual: workout.totalDuration, goal: totalGoal)
    }

    public var headerMetrics: [HeaderMetric] {
        [
            HeaderMetric(title: "DIST", value: DistanceFormatter.short(workout.totalDistanceMeters), tint: .neutral),
            HeaderMetric(title: "PACE", value: DurationFormatter.pace(workout.averageRunPaceSecondsPerKm), tint: .neutral),
            HeaderMetric(title: "AVG HR", value: workout.averageHeartRate.map(String.init) ?? "—", tint: .neutral),
            HeaderMetric(title: "MAX HR", value: workout.maxHeartRate.map(String.init) ?? "—", tint: .neutral)
        ]
    }

    public var sections: [RoundSection] {
        var result: [RoundSection] = []
        var pendingRunRecords: [SegmentRecord] = []
        var runIndex = 0
        var stationIndex = 0

        for record in workout.segments {
            switch record.type {
            case .run:
                runIndex += 1
                pendingRunRecords = [record]

            case .roxZone:
                if pendingRunRecords.isEmpty {
                    runIndex += 1
                }
                pendingRunRecords.append(record)

            case .station:
                stationIndex += 1
                let runGroup = pendingRunRecords.isEmpty
                    ? nil
                    : makeRunGroup(index: runIndex, records: pendingRunRecords)
                let station = makeStationItem(index: stationIndex, record: record)
                result.append(
                    RoundSection(
                        id: "round-\(stationIndex)",
                        runGroup: runGroup,
                        station: station
                    )
                )
                pendingRunRecords = []
            }
        }

        if !pendingRunRecords.isEmpty {
            result.append(
                RoundSection(
                    id: "round-tail-\(runIndex)",
                    runGroup: makeRunGroup(index: runIndex, records: pendingRunRecords),
                    station: nil
                )
            )
        }

        return result
    }

    public var shareText: String {
        var lines = [
            "HYROX \(titleText)",
            "Total: \(totalTimeText)",
            "Goal: \(totalGoalText)",
            "Delta: \(totalDelta.text)",
            "Distance: \(DistanceFormatter.short(workout.totalDistanceMeters))",
            "Avg Pace: \(DurationFormatter.pace(workout.averageRunPaceSecondsPerKm))"
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

    private func makeRunGroup(index: Int, records: [SegmentRecord]) -> RunGroupItem {
        let combinedDuration = records.reduce(0) { $0 + $1.activeDuration }
        let combinedGoal = records.compactMap(\.goalDurationSeconds).reduce(0, +)
        let delta = combinedGoal > 0
            ? goalDelta(actual: combinedDuration, goal: combinedGoal)
            : GoalDelta(text: "—", tone: .neutral, seconds: nil)

        let detailItems = records.map { record in
            switch record.type {
            case .run:
                return DetailItem(
                    id: record.id,
                    title: "Run \(index)",
                    subtitle: DistanceFormatter.short(record.plannedDistanceMeters ?? record.distanceMeters),
                    durationText: DurationFormatter.ms(record.activeDuration),
                    delta: goalDelta(actual: record.activeDuration, goal: record.goalDurationSeconds),
                    accent: .run
                )

            case .roxZone:
                return DetailItem(
                    id: record.id,
                    title: "Rox Zone",
                    subtitle: "Transition",
                    durationText: DurationFormatter.ms(record.activeDuration),
                    delta: goalDelta(actual: record.activeDuration, goal: record.goalDurationSeconds),
                    accent: .roxZone
                )

            case .station:
                return DetailItem(
                    id: record.id,
                    title: workout.resolvedStationDisplayName(for: record) ?? "Station",
                    subtitle: nil,
                    durationText: DurationFormatter.ms(record.activeDuration),
                    delta: goalDelta(actual: record.activeDuration, goal: record.goalDurationSeconds),
                    accent: .station
                )
            }
        }

        let hasRox = records.contains { $0.type == .roxZone }
        return RunGroupItem(
            id: "run-group-\(index)",
            index: index,
            title: hasRox ? "RUN \(index) + ROX" : "RUN \(index)",
            subtitle: hasRox ? "Running and transition" : "Running segment",
            durationText: DurationFormatter.ms(combinedDuration),
            delta: delta,
            detailItems: detailItems
        )
    }

    private func makeStationItem(index: Int, record: SegmentRecord) -> StationItem {
        StationItem(
            id: record.id,
            index: index,
            title: workout.resolvedStationDisplayName(for: record) ?? "Station \(index)",
            subtitle: record.stationDisplayName,
            durationText: DurationFormatter.ms(record.activeDuration),
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
