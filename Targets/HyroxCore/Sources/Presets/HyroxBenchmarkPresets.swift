//
//  HyroxBenchmarkPresets.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

// MARK: - PFT 벤치마크 템플릿

/// 공식 PFT 를 그대로 옮긴 템플릿.
///
/// 프리셋(`HyroxPresets.all`)·훈련 세션과 목록을 나눈다. 프리셋은 "대회 한 번", 세션은
/// "이번 주에 세 번", PFT 는 "지금 내 수준을 재는 한 번" 이라 화면에서 섞이면 안 된다.
///
/// 실행 자체는 기존 흐름을 그대로 쓴다 — 여기서 만드는 것은 평범한 `WorkoutTemplate` 이다.
extension HyroxPresets {

    /// 공식 PFT 템플릿.
    ///
    /// 구성은 프로토콜 그대로다: 1 km 런 → 버피 브로드 점프 50 → 런지 100 m →
    /// 로잉 1 km → 핸드 릴리즈 푸시업 30 → 월볼 100. 전환 구간(록스존)은 두지 않는다 —
    /// PFT 는 이어서 하는 한 덩어리라 구간을 끊으면 기록이 실제와 달라진다.
    ///
    /// - Parameters:
    ///   - division: 월볼 무게를 가져올 디비전. 생략하면 무게를 비워 둔다(자기 디비전 공으로).
    ///   - name: 템플릿 이름. 앱 타겟이 번들에서 읽어 넘긴다.
    ///   - stepName: 구간 이름. 대회에 없는 종목(푸시업)의 표시 이름으로 쓰인다.
    public static func pftBenchmark(
        for division: HyroxDivision? = nil,
        name: String = PFTBenchmark.defaultName,
        stepName: (PFTStep) -> String = { $0.defaultName }
    ) -> WorkoutTemplate {

        let segments = PFTStep.allCases.enumerated().map { index, step -> WorkoutSegment in
            var segment: WorkoutSegment

            switch step.segmentType {
            case .run:
                segment = .run(distanceMeters: step.runDistanceMeters ?? 1000)

            case .station:
                segment = .station(
                    step.stationKind(customName: stepName(step)) ?? .custom(name: stepName(step)),
                    target: step.target,
                    weightKg: weightKg(for: step, division: division)
                )

            case .roxZone:
                segment = .roxZone()
            }

            segment.goalDurationSeconds = Self.pftGoalSeconds(for: step)
            return WorkoutSegment(
                id: PFTBenchmark.segmentId(at: index),
                type: segment.type,
                distanceMeters: segment.distanceMeters,
                goalDurationSeconds: segment.goalDurationSeconds,
                stationKind: segment.stationKind,
                stationTarget: segment.stationTarget,
                weightKg: segment.weightKg,
                weightNote: segment.weightNote
            )
        }

        return WorkoutTemplate(
            id: PFTBenchmark.templateId,
            name: name,
            // 훈련 세션과 같은 이유로 디비전을 달지 않는다 — `TemplateGoalOverrideStore` 가
            // 디비전을 키로 쓰기 때문에, 디비전을 달면 같은 디비전 프리셋의 목표를 덮어쓴다.
            division: nil,
            segments: segments,
            usesRoxZone: false,
            createdAt: benchmarkFixedCreatedAt,
            isBuiltIn: true
        )
    }

    /// PFT 무게. 월볼만 디비전을 따른다 — 나머지 구간은 맨몸이거나 기구가 정해져 있다.
    private static func weightKg(for step: PFTStep, division: HyroxDivision?) -> Double? {
        guard step == .wallBalls, let division else { return nil }
        return HyroxDivisionSpec.stations(for: division)
            .first { $0.kind == .wallBalls }?
            .weightKg
    }

    /// 구간 기본 목표 시간(초).
    ///
    /// 합계 21:45 로, 보도된 기준 구간(15–35분)의 한가운데다. 개인 기록이 아니라
    /// "이 정도면 가운데" 라는 출발점일 뿐이고, 실행 전에 목표 화면에서 바꿀 수 있다.
    static func pftGoalSeconds(for step: PFTStep) -> TimeInterval {
        switch step {
        case .run: return 270
        case .burpeeBroadJumps: return 240
        case .lunges: return 180
        case .row: return 225
        case .pushUps: return 90
        case .wallBalls: return 300
        }
    }

    /// 벤치마크·릴레이 템플릿의 고정 생성 시각 (2026-01-01 UTC).
    ///
    /// 훈련 세션과 같은 이유다 — 호출할 때마다 새로 조립되므로 생성 시각이 매번 달라지면
    /// 같은 템플릿이 서로 다른 값으로 취급된다(화면 diff · 가민 전송).
    static let benchmarkFixedCreatedAt = Date(timeIntervalSince1970: 1_767_225_600)
}

// MARK: - 릴레이 템플릿

extension HyroxPresets {

    /// 릴레이 한 사람이 실제로 뛰는 구간 템플릿 — 2 × (1 km + 스테이션).
    ///
    /// 릴레이는 `HyroxDivision` 에 케이스를 더하지 않고 여기 템플릿과 `TeamSplitPlan` 으로만
    /// 표현한다. 무게는 릴레이 규칙대로 **성별 Open** 을 쓰고, 혼성은 슬롯마다 자기 성별
    /// Open 을 쓴다(`RelayDivision.weightDivision(forSlot:)`).
    ///
    /// 두 구간 사이에는 실제로 나머지 세 명이 도는 시간만큼 쉬게 된다. 템플릿은 그 휴식을
    /// 표현하지 않으므로, 혼자 이어서 돌리면 대회보다 훨씬 힘든 훈련이 된다 — 의도된 쓰임이다.
    ///
    /// - Parameters:
    ///   - slot: 팀에서 몇 번째로 도는지(0부터). 기본 순번대로 스테이션이 배정된다.
    ///   - division: 릴레이 디비전.
    ///   - name: 템플릿 이름. 앱 타겟이 번들에서 읽어 넘긴다.
    public static func relayLeg(
        slot: Int,
        division: RelayDivision,
        name: String? = nil
    ) -> WorkoutTemplate {

        let memberCount = division.memberCount
        let normalizedSlot = memberCount > 0 ? ((slot % memberCount) + memberCount) % memberCount : 0
        let specs = HyroxDivisionSpec.stations(for: division.weightDivision(forSlot: normalizedSlot))

        // 기본 순번(1 → 2 → 3 → 4 → 1 → …)에서 이 슬롯이 맡는 두 구간.
        let indices = stride(from: normalizedSlot, to: specs.count, by: memberCount)
        let stations = indices.compactMap { index -> WorkoutSegment? in
            guard specs.indices.contains(index) else { return nil }
            let spec = specs[index]
            return .station(
                spec.kind,
                target: spec.target,
                weightKg: spec.weightKg,
                weightNote: spec.weightNote
            )
        }

        var segments: [WorkoutSegment] = []
        for (index, station) in stations.enumerated() {
            segments.append(.run(distanceMeters: WorkoutTemplate.standardRunDistanceMeters))
            segments.append(.roxZone())
            segments.append(station)
            if index < stations.count - 1 {
                segments.append(.roxZone())
            }
        }

        let stable = segments.enumerated().map { index, segment in
            WorkoutSegment(
                id: relayLegSegmentId(slot: normalizedSlot, at: index),
                type: segment.type,
                distanceMeters: segment.distanceMeters,
                goalDurationSeconds: segment.goalDurationSeconds,
                stationKind: segment.stationKind,
                stationTarget: segment.stationTarget,
                weightKg: segment.weightKg,
                weightNote: segment.weightNote
            )
        }

        return WorkoutTemplate(
            id: relayLegTemplateId(slot: normalizedSlot),
            name: name ?? "\(division.displayName) — \(TeamEntry.defaultMemberName(forSlot: normalizedSlot))",
            division: nil,
            segments: stable,
            usesRoxZone: true,
            createdAt: benchmarkFixedCreatedAt,
            isBuiltIn: true
        )
    }

    /// 릴레이 4인 전원의 구간 템플릿.
    public static func relayLegs(
        for division: RelayDivision,
        name: (Int) -> String? = { _ in nil }
    ) -> [WorkoutTemplate] {
        (0..<division.memberCount).map { relayLeg(slot: $0, division: division, name: name($0)) }
    }

    /// 릴레이 구간 템플릿의 고정 ID. 슬롯마다 다르다.
    public static func relayLegTemplateId(slot: Int) -> UUID {
        UUID(uuidString: relayLegIdString(slot: slot)) ?? UUID()
    }

    static func relayLegSegmentId(slot: Int, at index: Int) -> UUID {
        guard (0..<0xFF).contains(index) else { return UUID() }
        let base = relayLegIdString(slot: slot)
        return UUID(uuidString: String(base.dropLast(2)) + String(format: "%02X", index)) ?? UUID()
    }

    /// PFT(`…9D01FF`) 와 같은 네임스페이스, 다른 번호대(`…9D1<slot>FF`)를 쓴다.
    private static func relayLegIdString(slot: Int) -> String {
        let clamped = min(max(0, slot), 3)
        return "9D2C6B10-3F84-4A57-8E41-7C0B5A9D1\(clamped)FF"
    }
}
