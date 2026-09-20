//
//  HyroxTrainingSessions.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

// MARK: - 훈련 세션 라이브러리

/// 대회 준비 기간에 반복해서 돌리는 빌트인 훈련 세션.
///
/// 프리셋(`HyroxPresets.all`)과는 목록을 분리한다. 프리셋은 "대회 한 번",
/// 세션은 "이번 주에 세 번" 하는 물건이라 화면에서도 섞이면 안 된다.
///
/// 무게는 언제나 `HyroxDivisionSpec` 값을 그대로 쓴다(룰북이 바뀌면 세션도 같이 바뀐다).
/// 반면 횟수·거리는 훈련량에 맞춰 스펙 값에서 *비율로* 줄인다 — 어떤 세션이 몇 %인지는
/// 각 빌더에 적어 뒀다.
extension HyroxPresets {

    /// 해당 디비전 기준으로 조립한 전체 훈련 세션 목록.
    /// - Parameters:
    ///   - division: 무게·기본 횟수를 가져올 디비전.
    ///   - localizedName: 세션 이름 지역화. 앱 타겟이 번들에서 읽어 넘긴다.
    ///     생략하면 영문 기본 이름(`TrainingSessionKind.defaultName`)을 쓴다.
    public static func trainingSessions(
        for division: HyroxDivision,
        localizedName: (TrainingSessionKind) -> String = { $0.defaultName }
    ) -> [WorkoutTemplate] {
        TrainingSessionKind.allCases.map {
            trainingSession($0, for: division, localizedName: localizedName)
        }
    }

    /// 훈련 세션 하나를 조립한다.
    public static func trainingSession(
        _ kind: TrainingSessionKind,
        for division: HyroxDivision,
        localizedName: (TrainingSessionKind) -> String = { $0.defaultName }
    ) -> WorkoutTemplate {
        let plan = TrainingSessionBuilder.plan(for: kind, division: division)
        return WorkoutTemplate(
            id: kind.templateId,
            name: localizedName(kind),
            // 세션에는 디비전을 달지 않는다. `TemplateGoalOverrideStore` 가 디비전을
            // 키로 쓰기 때문에, 디비전을 달면 세션 목표가 같은 디비전 프리셋의 목표를
            // 덮어쓴다.
            division: nil,
            segments: TrainingSessionBuilder.withStableIds(plan.segments, of: kind),
            usesRoxZone: plan.usesRoxZone,
            // 세션은 매 호출마다 새로 조립된다. 생성 시각이 매번 달라지면 같은 세션이
            // 서로 다른 값으로 취급되므로(Equatable/가민 전송) 고정 시각을 쓴다.
            createdAt: TrainingSessionBuilder.fixedCreatedAt,
            isBuiltIn: true
        )
    }
}

// MARK: - Builder

private enum TrainingSessionBuilder {

    struct Plan {
        let segments: [WorkoutSegment]
        let usesRoxZone: Bool
    }

    /// 세션 템플릿의 고정 생성 시각 (2026-01-01 UTC).
    static let fixedCreatedAt = Date(timeIntervalSince1970: 1_767_225_600)

    static func plan(for kind: TrainingSessionKind, division: HyroxDivision) -> Plan {
        switch kind {
        case .compromisedRun: return compromisedRun(division: division)
        case .halfSimulation: return halfSimulation(division: division)
        case .stationIntervals: return stationIntervals(division: division)
        case .roxZoneDrill: return roxZoneDrill(division: division)
        case .wallBallLadder: return wallBallLadder(division: division)
        }
    }

    // MARK: - 세션

    /// 컴프로마이즈드 런 — 1 km 런 + 샌드백 런지(대회 절반 거리) 4 라운드.
    ///
    /// HYROX 기록을 가장 크게 가르는 건 스테이션 자체가 아니라 *스테이션 직후의 런* 이다.
    /// 그중에서도 런지 → 런(스테이션 7 → 런 8) 구간이 가장 무너지기 쉬워, 그 전환만
    /// 떼어내 반복한다. 대회 볼륨(100 m)의 절반을 4번 하므로 총 런지 거리는 대회의 2배,
    /// 런은 4 km 다.
    private static func compromisedRun(division: HyroxDivision) -> Plan {
        let lunges = spec(.sandbagLunges, in: division)
        let stations = (0..<4).map { _ in stationSegment(lunges, volumeFactor: 0.5) }
        return Plan(
            segments: runStationRounds(runDistanceMeters: 1000, stations: stations),
            usesRoxZone: true
        )
    }

    /// 하프 시뮬레이션 — 표준 코스 앞 절반(런 1~4 + 스테이션 1~4), 대회 볼륨 그대로.
    ///
    /// 풀 시뮬은 회복에만 며칠이 드는 반면, 앞 절반은 주중에도 돌릴 수 있다.
    /// 스키에르그 → 슬레드 푸시 → 슬레드 풀 → 버피는 초반 페이스 판단이 가장 크게
    /// 갈리는 구간이라 반복 가치가 높다.
    private static func halfSimulation(division: HyroxDivision) -> Plan {
        let specs = Array(HyroxDivisionSpec.stations(for: division).prefix(4))
        let stations = specs.map { stationSegment($0) }
        return Plan(
            segments: runStationRounds(runDistanceMeters: 1000, stations: stations),
            usesRoxZone: true
        )
    }

    /// 스테이션 인터벌 — 월볼 · 버피 브로드 점프 · 샌드백 런지를 대회 절반 볼륨으로 3 라운드.
    ///
    /// 세 종목은 상위권과 중위권의 누적 시간 차이가 가장 크게 벌어지는 구간이다.
    /// 런이 없어 순수 스테이션 처리 속도만 올린다.
    private static func stationIntervals(division: HyroxDivision) -> Plan {
        let kinds: [StationKind] = [.wallBalls, .burpeeBroadJumps, .sandbagLunges]
        let segments = (0..<3).flatMap { _ in
            kinds.map { stationSegment(spec($0, in: division), volumeFactor: 0.5) }
        }
        // 런이 없으니 록스존(런↔스테이션 전환)도 없다.
        return Plan(segments: segments, usesRoxZone: false)
    }

    /// 록스존 전환 드릴 — 400 m 런 + 록스존 + 스테이션 진입(대회 1/4 볼륨) 4 라운드.
    ///
    /// 진입 동작이 서로 다른 4종(머신 · 바닥 · 들어올리기 · 벽)을 한 번씩 돌면서
    /// "런에서 내려와 첫 렙까지" 의 시간을 줄이는 게 목적이라, 스테이션 볼륨은 짧게 둔다.
    private static func roxZoneDrill(division: HyroxDivision) -> Plan {
        let kinds: [StationKind] = [.skiErg, .burpeeBroadJumps, .farmersCarry, .wallBalls]
        let stations = kinds.map { stationSegment(spec($0, in: division), volumeFactor: 0.25) }
        return Plan(
            segments: runStationRounds(runDistanceMeters: 400, stations: stations),
            usesRoxZone: true
        )
    }

    /// 월볼 사다리 — 대회 볼륨(디비전 스펙 횟수)을 30/25/20/15/10 % 로 쪼갠 내림차순 5 세트.
    ///
    /// 마지막 스테이션에서 실제로 벌어지는 일(세트가 점점 잘게 쪼개짐)을 그대로 연습한다.
    /// 총 횟수는 대회와 같고 무게도 스펙 그대로다.
    private static func wallBallLadder(division: HyroxDivision) -> Plan {
        let wallBalls = spec(.wallBalls, in: division)
        return Plan(segments: ladderSegments(for: wallBalls), usesRoxZone: false)
    }

    // MARK: - 조립 도우미

    /// 세그먼트 ID 를 세션·순번으로 고정한다.
    /// `WorkoutSegment` 편의 생성자는 매번 새 UUID 를 만들기 때문에, 그대로 두면
    /// 같은 세션을 두 번 조립했을 때 값이 달라진다(화면 diff·동기화가 흔들린다).
    static func withStableIds(_ segments: [WorkoutSegment], of kind: TrainingSessionKind) -> [WorkoutSegment] {
        segments.enumerated().map { index, segment in
            WorkoutSegment(
                id: kind.segmentId(at: index),
                type: segment.type,
                distanceMeters: segment.distanceMeters,
                goalDurationSeconds: segment.goalDurationSeconds,
                stationKind: segment.stationKind,
                stationTarget: segment.stationTarget,
                weightKg: segment.weightKg,
                weightNote: segment.weightNote
            )
        }
    }

    private static let ladderShares: [Double] = [0.30, 0.25, 0.20, 0.15, 0.10]

    private static func ladderSegments(for stationSpec: HyroxStationSpec) -> [WorkoutSegment] {
        guard case .reps(let total) = stationSpec.target, total > 0 else {
            // 룰북이 월볼을 횟수가 아닌 목표로 바꾸면 비율만 적용한다.
            return ladderShares.map { stationSegment(stationSpec, volumeFactor: $0) }
        }

        var remaining = total
        var segments: [WorkoutSegment] = []
        for (index, share) in ladderShares.enumerated() {
            let isLast = index == ladderShares.count - 1
            // 마지막 세트가 반올림 오차를 흡수해 합계가 항상 대회 볼륨과 같아진다.
            let reps = isLast
                ? max(1, remaining)
                : max(1, Int((Double(total) * share).rounded()))
            remaining -= reps
            segments.append(
                stationSegment(stationSpec, volumeFactor: share, targetOverride: .reps(count: reps))
            )
        }
        return segments
    }

    /// `런 → 록스존 → 스테이션 → 록스존` 라운드를 이어 붙인다.
    /// 마지막 퇴장 록스존은 두지 않는다 — 대회 구조(31 세그먼트)와 같은 규칙이다.
    private static func runStationRounds(
        runDistanceMeters: Double,
        stations: [WorkoutSegment]
    ) -> [WorkoutSegment] {
        var segments: [WorkoutSegment] = []
        for (index, station) in stations.enumerated() {
            segments.append(.run(distanceMeters: runDistanceMeters))
            segments.append(.roxZone())
            segments.append(station)
            if index < stations.count - 1 {
                segments.append(.roxZone())
            }
        }
        return segments
    }

    private static func stationSegment(
        _ stationSpec: HyroxStationSpec,
        volumeFactor: Double = 1,
        targetOverride: StationTarget? = nil
    ) -> WorkoutSegment {
        var segment = WorkoutSegment.station(
            stationSpec.kind,
            target: targetOverride ?? scaled(stationSpec.target, by: volumeFactor),
            // 무게는 절대 줄이지 않는다 — 훈련 자극의 핵심이고 룰북 값이다.
            weightKg: stationSpec.weightKg,
            weightNote: stationSpec.weightNote
        )
        segment.goalDurationSeconds = stationGoalSeconds(volumeFactor: volumeFactor)
        return segment
    }

    /// 볼륨을 줄인 만큼 기본 목표 시간도 줄인다. 너무 짧아지지 않도록 30초를 하한으로 둔다.
    private static func stationGoalSeconds(volumeFactor: Double) -> TimeInterval {
        let full = WorkoutSegment.defaultGoalDurationSeconds(for: .station, distanceMeters: nil)
        return max(30, (full * volumeFactor).rounded())
    }

    /// 스테이션 목표를 비율로 줄인다. 거리는 5 m 격자에 맞춰 반올림해 실제 레인 길이와 맞춘다.
    private static func scaled(_ target: StationTarget, by factor: Double) -> StationTarget {
        guard factor < 1 else { return target }
        switch target {
        case .distance(let meters):
            let grid: Double = 5
            let value = (meters * factor / grid).rounded() * grid
            return .distance(meters: max(grid, value))
        case .reps(let count):
            return .reps(count: max(1, Int((Double(count) * factor).rounded())))
        case .duration(let seconds):
            return .duration(seconds: max(10, (seconds * factor).rounded()))
        case .none:
            return .none
        }
    }

    /// 디비전 스펙에서 해당 스테이션을 찾는다. 스펙에 없으면(룰북 변경 등)
    /// 종목 기본 목표로 대체해 세션이 사라지지 않게 한다.
    private static func spec(_ kind: StationKind, in division: HyroxDivision) -> HyroxStationSpec {
        HyroxDivisionSpec.stations(for: division).first { $0.kind == kind }
            ?? HyroxStationSpec(kind: kind, target: kind.defaultTarget)
    }
}
