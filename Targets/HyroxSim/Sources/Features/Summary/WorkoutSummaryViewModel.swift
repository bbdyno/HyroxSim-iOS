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

    /// 심박 존 계산 기준. 설정에서 받아오기 전까지는 nil 이고, 그때는 존 분포를 숨긴다.
    /// (예전에는 190 이 하드코딩되어 있어서, 남의 최대심박으로 그린 존이 화면에 나갔다.)
    private let maxHeartRate: Int?

    /// 격차 분석이 비교 대상으로 삼는 목표.
    private let gapTarget: GapTarget?

    /// 계산 비용이 있는 값이라 init 에서 한 번만 구해 둔다.
    private let gapAnalysis: GapAnalysis?

    public init(
        workout: CompletedWorkout,
        maxHeartRate: Int? = nil,
        gapTarget: GapTarget? = nil,
        gapReferenceProvider: (any GapReferenceProviding)? = nil
    ) {
        self.workout = workout
        self.maxHeartRate = maxHeartRate

        // 목표를 따로 주지 않으면 운동 시작 시점에 찍힌 구간 목표의 합을 목표로 본다.
        let resolvedTarget: GapTarget?
        if let gapTarget {
            resolvedTarget = gapTarget
        } else {
            let goals = workout.segments.compactMap(\.goalDurationSeconds)
            resolvedTarget = goals.isEmpty ? nil : .finishTime(seconds: goals.reduce(0, +))
        }
        self.gapTarget = resolvedTarget

        let provider: (any GapReferenceProviding)?
        if let gapReferenceProvider {
            provider = gapReferenceProvider
        } else {
            // 번들 데이터를 못 읽으면 격차 분석만 빠지고 나머지 요약은 그대로 보여준다.
            provider = try? PacePlannerGapReferenceProvider()
        }

        if let provider, let resolvedTarget {
            self.gapAnalysis = GapAnalyzer(referenceProvider: provider)
                .analyze(workout, target: resolvedTarget)
        } else {
            self.gapAnalysis = nil
        }
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

    // MARK: - 격차 분석 카드

    /// "목표까지 되찾을 수 있는 시간" 카드의 한 줄.
    public struct GapRow: Hashable, Identifiable {
        public let id: String
        public let title: String
        /// 되찾을 수 있는 시간 (예: `−1:36`).
        public let deltaText: String
        /// 전체 격차에서의 비중 문구.
        public let shareText: String
        /// 막대 길이. 가장 큰 손실 구간을 1.0 으로 둔 상대값.
        public let barRatio: Double
        public let accent: AccentKind
    }

    public struct GapCard: Hashable {
        public enum Status: Hashable {
            /// 공식 코스가 아닌 기록 — 참조 데이터가 맞지 않아 분석하지 않는다.
            case unsupportedCourse
            /// 목표가 없어 비교 대상이 없다.
            case noGoal
            /// 목표가 참조 데이터 범위 밖이다.
            case noReference
            /// 이미 목표보다 빠르다.
            case goalMet
            /// 되찾을 구간이 있다.
            case gaps
        }

        public let status: Status
        public let title: String
        /// 목표 시간(과 퍼센타일).
        public let subtitle: String?
        /// 상태 안내 문구. 구간 목록이 있을 때는 총 회수 가능 시간.
        public let message: String?
        /// 상위 3개 구간.
        public let rows: [GapRow]
        /// 생략한 나머지 구간 요약.
        public let remainderText: String?

        /// 커스텀 코스에서는 카드 자체를 띄우지 않는다.
        public var isVisible: Bool { status != .unsupportedCourse }
    }

    public var titleText: String {
        workout.templateName
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

    /// 심박 존 분포. 최대 심박을 모르면 빈 배열 — 화면에서도 존 섹션을 생략한다.
    public var heartRateZoneDistribution: [ZoneItem] {
        guard let maxHeartRate, maxHeartRate > 0 else { return [] }

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

    // MARK: - 격차 분석

    /// 화면에 그릴 격차 분석 카드 상태.
    ///
    /// 판정 순서가 곧 우선순위다. 커스텀 코스에는 목표를 설정하라는 안내조차 의미가 없으므로
    /// 코스 판정을 먼저 한다.
    public var gapCard: GapCard {
        let title = HyroxSimStrings.Localizable.Summary.Gap.title

        guard workout.isStandardHyroxCourse else {
            return GapCard(
                status: .unsupportedCourse,
                title: title,
                subtitle: nil,
                message: nil,
                rows: [],
                remainderText: nil
            )
        }

        guard gapTarget != nil else {
            return GapCard(
                status: .noGoal,
                title: title,
                subtitle: nil,
                message: HyroxSimStrings.Localizable.Summary.Gap.noGoal,
                rows: [],
                remainderText: nil
            )
        }

        guard let analysis = gapAnalysis, !analysis.isReferenceExtrapolated else {
            return GapCard(
                status: .noReference,
                title: title,
                subtitle: nil,
                message: HyroxSimStrings.Localizable.Summary.Gap.noReference,
                rows: [],
                remainderText: nil
            )
        }

        let subtitle = gapSubtitle(for: analysis)
        let behind = analysis.behindItems

        guard !behind.isEmpty, !analysis.isGoalAlreadyMet else {
            return GapCard(
                status: .goalMet,
                title: title,
                subtitle: subtitle,
                message: HyroxSimStrings.Localizable.Summary.Gap.goalMetFormat(
                    reclaimTimeText(abs(analysis.totalGapSeconds), signed: false)
                ),
                rows: [],
                remainderText: nil
            )
        }

        let maxDelta = behind.first?.deltaSeconds ?? 0
        let top = Array(behind.prefix(Self.gapRowLimit))
        let rows = top.map { item in
            GapRow(
                id: gapRowIdentifier(for: item.kind),
                title: gapRowTitle(for: item.kind),
                deltaText: reclaimTimeText(item.deltaSeconds),
                shareText: HyroxSimStrings.Localizable.Summary.Gap.shareFormat(Int((item.share * 100).rounded())),
                barRatio: maxDelta > 0 ? min(1, max(0, item.deltaSeconds / maxDelta)) : 0,
                accent: gapRowAccent(for: item.kind)
            )
        }

        let remaining = behind.dropFirst(Self.gapRowLimit)
        let remainderText: String?
        if remaining.isEmpty {
            remainderText = nil
        } else {
            let remainingSeconds = remaining.reduce(0) { $0 + $1.deltaSeconds }
            remainderText = HyroxSimStrings.Localizable.Summary.Gap.remainderFormat(
                remaining.count,
                reclaimTimeText(remainingSeconds)
            )
        }

        return GapCard(
            status: .gaps,
            title: title,
            subtitle: subtitle,
            message: HyroxSimStrings.Localizable.Summary.Gap.headlineFormat(
                reclaimTimeText(analysis.recoverableSeconds, signed: false)
            ),
            rows: rows,
            remainderText: remainderText
        )
    }

    /// 공유 카드에 얹을 구간 하이라이트(상위 3개). 분석이 없으면 빈 배열.
    public var gapHighlights: [GapRow] {
        let card = gapCard
        return card.status == .gaps ? card.rows : []
    }

    public var divisionText: String? {
        workout.division?.displayName
    }

    // MARK: - 공유

    /// 공유 카드 이미지를 그릴 재료.
    var shareCardContent: SummaryShareCardContent {
        SummaryShareCardContent(
            title: titleText,
            division: divisionText,
            dateText: dateText,
            totalTimeText: totalTimeText,
            goalText: totalGoalText == "—" ? nil : totalGoalText,
            deltaText: totalGoalText == "—" ? nil : totalDelta.text,
            deltaTone: totalDelta.tone,
            highlightTitle: gapCard.status == .gaps ? gapCard.title : nil,
            highlights: gapHighlights.map {
                SummaryShareCardContent.Highlight(
                    title: $0.title,
                    valueText: $0.deltaText,
                    ratio: $0.barRatio
                )
            },
            fallbackHighlights: slowestStationHighlights
        )
    }

    /// 격차 분석을 쓸 수 없을 때 공유 카드에 넣는 대체 항목: 오래 걸린 스테이션 3개.
    private var slowestStationHighlights: [SummaryShareCardContent.Highlight] {
        let slowest = stationItems.sorted { $0.durationSeconds > $1.durationSeconds }.prefix(3)
        guard let longest = slowest.first?.durationSeconds, longest > 0 else { return [] }
        return slowest.map {
            SummaryShareCardContent.Highlight(
                title: $0.name,
                valueText: $0.durationText,
                ratio: $0.durationSeconds / longest
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

        let highlights = gapHighlights
        if !highlights.isEmpty {
            lines.append("")
            lines.append(HyroxSimStrings.Localizable.Summary.Gap.title)
            for highlight in highlights {
                lines.append("\(highlight.title): \(highlight.deltaText)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 격차 분석 보조

    /// 카드에 노출할 구간 수. 나머지는 한 줄로 접는다.
    private static let gapRowLimit = 3

    private func gapSubtitle(for analysis: GapAnalysis) -> String {
        let goalText = DurationFormatter.hms(analysis.targetTotalSeconds)
        guard let percentile = analysis.targetPercentile else {
            return HyroxSimStrings.Localizable.Summary.Gap.subtitleGoalFormat(goalText)
        }
        return HyroxSimStrings.Localizable.Summary.Gap.subtitleFormat(
            goalText,
            HyroxSimStrings.Localizable.PacePlanner.Percentile.format(Float(percentile))
        )
    }

    /// 되찾을 수 있는 시간 표기. 부호는 유니코드 마이너스를 써서 숫자 폭을 맞춘다.
    private func reclaimTimeText(_ seconds: TimeInterval, signed: Bool = true) -> String {
        // NaN·무한대가 들어와도 Int 변환에서 트랩이 나지 않도록 막는다.
        let magnitude = abs(seconds)
        let total = magnitude.isFinite ? Int(min(magnitude.rounded(), 359_999)) : 0
        let body = String(format: "%d:%02d", total / 60, total % 60)
        return signed ? "\u{2212}" + body : body
    }

    private func gapRowTitle(for kind: GapItem.Kind) -> String {
        switch kind {
        case .run:
            return HyroxSimStrings.Localizable.Summary.Gap.Row.run
        case .roxZone:
            return HyroxSimStrings.Localizable.Summary.Gap.Row.roxZone
        case .station(let station):
            return station.displayName
        }
    }

    private func gapRowAccent(for kind: GapItem.Kind) -> AccentKind {
        switch kind {
        case .run:
            return .run
        case .roxZone:
            return .roxZone
        case .station:
            return .station
        }
    }

    private func gapRowIdentifier(for kind: GapItem.Kind) -> String {
        switch kind {
        case .run:
            return "gap-run"
        case .roxZone:
            return "gap-rox"
        case .station(let station):
            return "gap-station-\(station.dataKey ?? station.displayName)"
        }
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

        // Individual Run/Rox detail items: no delta shown (합산 행에서만 표시)
        let noDelta = GoalDelta(text: "—", tone: .neutral, seconds: nil)
        let detailItems = records.compactMap { record in
            switch record.type {
            case .run:
                return DetailItem(
                    id: record.id,
                    title: "Run \(index)",
                    subtitle: DistanceFormatter.short(record.plannedDistanceMeters ?? record.distanceMeters),
                    durationText: DurationFormatter.hms(record.activeDuration),
                    delta: noDelta,
                    accent: .run
                )

            case .roxZone:
                return DetailItem(
                    id: record.id,
                    title: "Rox Zone",
                    subtitle: "Transition",
                    durationText: DurationFormatter.hms(record.activeDuration),
                    delta: noDelta,
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
