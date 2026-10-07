//
//  RacePaceCard.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 대회 당일에 들고 보는 "구간별 목표 시간표".
///
/// 운동 화면의 델타 계산과 **같은 블록 규칙**을 쓴다. HYROX 코스는
/// `Run → RoxZone(입장) → Station → RoxZone(퇴장) → Run …` 으로 이어지는데,
/// 전환 구간(RoxZone)은 따로 세지 않고 자기 블록의 Run 에 합산한다.
/// 선수가 트랙에서 보는 단위가 "런"과 "스테이션" 둘뿐이기 때문이다.
///
/// 각 행은 구간 목표(`goalSeconds`) 와 **누적 목표 시각**(`cumulativeSeconds`) 을 함께 갖는다.
/// 대회장에서는 손목시계의 총 경과 시간과 이 누적값만 비교하면 되므로,
/// 구간 목표보다 누적값이 실제로 더 자주 쓰인다. (예: "Run 3 끝나면 24:10")
///
/// 목표가 하나도 없는 템플릿도 정상 입력이다. 이때 모든 행의 목표는 `nil` 이고
/// `hasGoals` 가 `false` 가 된다 — 화면은 표 대신 안내를 보여주면 된다.
public struct RacePaceCard: Equatable, Sendable {

    /// 표의 한 줄이 무엇을 가리키는지.
    public enum RowKind: String, Codable, Hashable, Sendable {
        /// 런 블록. 앞뒤 RoxZone 목표가 합산돼 있다.
        case run
        /// 스테이션 8종 중 하나.
        case station
        /// 어느 런에도 붙지 못한 전환 구간(커스텀 템플릿에서만 나온다).
        case transition
    }

    public struct Row: Identifiable, Equatable, Sendable {
        /// 이 행을 대표하는 세그먼트 ID (런 블록이면 Run 세그먼트).
        public let id: UUID
        public let kind: RowKind
        /// 같은 종류 안에서의 순번 (RUN 3 → 3).
        public let order: Int
        /// 표에 찍히는 이름 ("RUN 3", "Wall Balls").
        public let title: String
        /// 부가 정보 ("1.00 km", "100 reps").
        public let detail: String?
        /// 이 구간 하나의 목표 시간. 목표가 없으면 nil.
        public let goalSeconds: TimeInterval?
        /// 이 구간이 끝나는 시점의 누적 목표 시각. 목표가 없으면 nil.
        public let cumulativeSeconds: TimeInterval?
        /// 런 블록의 목표 페이스(초/km). 런이 아니거나 거리를 모르면 nil.
        public let paceSecondsPerKm: Double?

        public init(
            id: UUID,
            kind: RowKind,
            order: Int,
            title: String,
            detail: String?,
            goalSeconds: TimeInterval?,
            cumulativeSeconds: TimeInterval?,
            paceSecondsPerKm: Double?
        ) {
            self.id = id
            self.kind = kind
            self.order = order
            self.title = title
            self.detail = detail
            self.goalSeconds = goalSeconds
            self.cumulativeSeconds = cumulativeSeconds
            self.paceSecondsPerKm = paceSecondsPerKm
        }
    }

    /// 카드 제목 (대회 이름 또는 템플릿 이름).
    public let title: String
    /// 부제 (디비전·날짜 등). 없으면 nil.
    public let subtitle: String?
    public let rows: [Row]
    /// 표 전체의 목표 합계. 목표가 하나도 없으면 nil.
    public let totalGoalSeconds: TimeInterval?
    /// 대회 목표에 맞추려고 템플릿 목표를 비율 조정했는지 여부.
    public let isScaledToRaceGoal: Bool

    /// 표시할 목표가 하나라도 있는지.
    public var hasGoals: Bool { totalGoalSeconds != nil }

    public init(
        title: String,
        subtitle: String?,
        rows: [Row],
        totalGoalSeconds: TimeInterval?,
        isScaledToRaceGoal: Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.rows = rows
        self.totalGoalSeconds = totalGoalSeconds
        self.isScaledToRaceGoal = isScaledToRaceGoal
    }

    // MARK: - 생성

    /// 템플릿에서 페이스 카드를 만든다.
    ///
    /// - Parameters:
    ///   - template: 구간 구성과 구간별 목표의 원본.
    ///   - title: 카드 제목. 비우면 템플릿 이름을 쓴다.
    ///   - subtitle: 부제 (디비전·대회 날짜 등).
    ///   - raceGoalSeconds: 대회 목표 완주 시간. 주면 템플릿 목표를 이 시간에 맞게
    ///     **비율 조정**한다. 목표 1:25:00 인 사람에게 1:30:00 짜리 표를 보여주면
    ///     대회장에서 그대로 오판하기 때문이다. 반올림 오차는 누적값 기준으로 흡수해
    ///     마지막 행의 누적값이 정확히 목표와 같아진다.
    public static func make(
        template: WorkoutTemplate,
        title: String? = nil,
        subtitle: String? = nil,
        raceGoalSeconds: TimeInterval? = nil
    ) -> RacePaceCard {
        let drafts = drafts(from: template)
        let baseTotal = drafts.compactMap(\.goalSeconds).reduce(0, +)
        let hasAnyGoal = drafts.contains { $0.goalSeconds != nil }

        var factor: Double = 1
        var isScaled = false
        if let raceGoalSeconds, raceGoalSeconds > 0, baseTotal > 0 {
            factor = raceGoalSeconds / baseTotal
            isScaled = abs(raceGoalSeconds - baseTotal) >= 1
        }

        var rows: [Row] = []
        var exactCumulative: Double = 0
        var roundedCumulative: Double = 0

        for draft in drafts {
            guard let goal = draft.goalSeconds else {
                rows.append(
                    Row(
                        id: draft.id,
                        kind: draft.kind,
                        order: draft.order,
                        title: draft.title,
                        detail: draft.detail,
                        goalSeconds: nil,
                        cumulativeSeconds: nil,
                        paceSecondsPerKm: nil
                    )
                )
                continue
            }

            exactCumulative += goal * factor
            let nextCumulative = exactCumulative.rounded()
            let rowGoal = nextCumulative - roundedCumulative
            roundedCumulative = nextCumulative

            rows.append(
                Row(
                    id: draft.id,
                    kind: draft.kind,
                    order: draft.order,
                    title: draft.title,
                    detail: draft.detail,
                    goalSeconds: rowGoal,
                    cumulativeSeconds: nextCumulative,
                    paceSecondsPerKm: paceSecondsPerKm(for: draft, factor: factor, blockGoal: rowGoal)
                )
            )
        }

        return RacePaceCard(
            title: title ?? template.name,
            subtitle: subtitle,
            rows: rows,
            totalGoalSeconds: hasAnyGoal ? roundedCumulative : nil,
            isScaledToRaceGoal: isScaled
        )
    }

    // MARK: - 내부 구성

    private struct Draft {
        let id: UUID
        let kind: RowKind
        let order: Int
        let title: String
        let detail: String?
        let goalSeconds: TimeInterval?
        /// 전환 구간을 뺀 런 자체의 목표. 페이스 계산에만 쓴다.
        let runOnlyGoalSeconds: TimeInterval?
        let runDistanceMeters: Double?
    }

    /// 런 목표 페이스. 전환 구간을 뺀 런 자체 목표를 거리로 나눈다.
    /// 런 목표가 따로 없으면(페이스 플래너가 블록 합산을 Run 에 몰아넣은 경우 포함)
    /// 블록 목표를 그대로 쓴다.
    private static func paceSecondsPerKm(
        for draft: Draft,
        factor: Double,
        blockGoal: TimeInterval
    ) -> Double? {
        guard draft.kind == .run,
              let distance = draft.runDistanceMeters,
              distance > 0 else { return nil }
        let base: TimeInterval
        if let runOnly = draft.runOnlyGoalSeconds, runOnly > 0 {
            base = runOnly * factor
        } else {
            base = blockGoal
        }
        guard base > 0 else { return nil }
        return base / (distance / 1000)
    }

    private static func drafts(from template: WorkoutTemplate) -> [Draft] {
        let segments = template.segments
        var drafts: [Draft] = []
        var runOrder = 0
        var stationOrder = 0
        var transitionOrder = 0
        var index = 0

        while index < segments.count {
            let segment = segments[index]

            switch segment.type {
            case .station:
                stationOrder += 1
                drafts.append(
                    Draft(
                        id: segment.id,
                        kind: .station,
                        order: stationOrder,
                        title: segment.stationKind?.displayName ?? "Station \(stationOrder)",
                        detail: stationDetail(for: segment),
                        goalSeconds: segment.goalDurationSeconds,
                        runOnlyGoalSeconds: nil,
                        runDistanceMeters: nil
                    )
                )
                index += 1

            case .run, .roxZone:
                guard let runIndex = owningRunIndex(for: index, in: segments) else {
                    // 어느 런에도 붙지 못한 전환 구간. 커스텀 템플릿에서만 나오며,
                    // 시간을 잃어버리지 않도록 자체 행으로 남긴다.
                    transitionOrder += 1
                    drafts.append(
                        Draft(
                            id: segment.id,
                            kind: .transition,
                            order: transitionOrder,
                            title: segment.type == .roxZone ? "ROX ZONE" : "RUN",
                            detail: segment.distanceMeters.map(DistanceFormatter.short),
                            goalSeconds: segment.goalDurationSeconds,
                            runOnlyGoalSeconds: nil,
                            runDistanceMeters: nil
                        )
                    )
                    index += 1
                    continue
                }

                // 이미 지나온 구간을 다시 세지 않도록 블록 범위를 현재 위치부터로 자른다.
                let start = max(blockStartIndex(runIndex: runIndex, in: segments), index)
                let end = max(blockEndIndex(runIndex: runIndex, in: segments), start)
                let run = segments[runIndex]
                let goals = segments[start...end].compactMap(\.goalDurationSeconds)
                runOrder += 1
                drafts.append(
                    Draft(
                        id: run.id,
                        kind: .run,
                        order: runOrder,
                        title: "RUN \(runOrder)",
                        detail: run.distanceMeters.map(DistanceFormatter.short),
                        goalSeconds: goals.isEmpty ? nil : goals.reduce(0, +),
                        runOnlyGoalSeconds: run.goalDurationSeconds,
                        runDistanceMeters: run.distanceMeters
                    )
                )
                index = end + 1
            }
        }

        return drafts
    }

    private static func stationDetail(for segment: WorkoutSegment) -> String? {
        var parts: [String] = []
        if let target = segment.stationTarget, target != .none {
            parts.append(target.formatted)
        }
        if let weight = segment.weightKg, weight > 0 {
            parts.append("\(DurationFormatter.safeInt(weight)) kg")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - 블록 계산 (운동 화면 델타 규칙과 동일)

    /// 이 Run/RoxZone 세그먼트가 속한 블록의 Run 인덱스.
    /// - Run: 자기 자신
    /// - RoxZone(입장, 다음이 Station): 바로 앞 Run
    /// - RoxZone(퇴장, 앞이 Station): 바로 뒤 Run
    static func owningRunIndex(for index: Int, in segments: [WorkoutSegment]) -> Int? {
        guard segments.indices.contains(index) else { return nil }
        switch segments[index].type {
        case .run:
            return index
        case .station:
            return nil
        case .roxZone:
            if index >= 1, segments[index - 1].type == .station {
                for i in (index + 1)..<segments.count {
                    if segments[i].type == .run { return i }
                    if segments[i].type == .station { return nil }
                }
                return nil
            }
            for i in stride(from: index - 1, through: 0, by: -1) {
                if segments[i].type == .run { return i }
                if segments[i].type == .station { return nil }
            }
            return nil
        }
    }

    static func blockStartIndex(runIndex: Int, in segments: [WorkoutSegment]) -> Int {
        if runIndex >= 1, segments[runIndex - 1].type == .roxZone {
            return runIndex - 1
        }
        return runIndex
    }

    static func blockEndIndex(runIndex: Int, in segments: [WorkoutSegment]) -> Int {
        let next = runIndex + 1
        if next < segments.count, segments[next].type == .roxZone {
            return next
        }
        return runIndex
    }
}
