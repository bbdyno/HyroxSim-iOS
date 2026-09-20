//
//  PFTBenchmark.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

// MARK: - 구성

/// 공식 PFT(Physical Fitness Test) 구간.
///
/// 순서·볼륨은 공식 프로토콜 그대로다:
/// 1 km 런 → 버피 브로드 점프 50 → 런지 100 m → 로잉 1 km → 핸드 릴리즈 푸시업 30 → 월볼 100.
///
/// 이름은 `HyroxCore` 가 문자열 리소스를 갖지 않으므로 *키* 만 노출하고, 실제 문구는
/// 앱 타겟의 `Localizable.strings` 가 갖는다(훈련 세션과 같은 방식).
public enum PFTStep: String, CaseIterable, Codable, Hashable, Sendable {
    case run
    case burpeeBroadJumps
    case lunges
    case row
    case pushUps
    case wallBalls

    public var segmentType: SegmentType {
        self == .run ? .run : .station
    }

    /// 대회 스테이션으로 그대로 이어지는 종목이면 그 종목.
    /// 푸시업처럼 대회에 없는 종목은 `nil` — `stationKind(customName:)` 이 커스텀으로 만든다.
    public var standardStation: StationKind? {
        switch self {
        case .run: return nil
        case .burpeeBroadJumps: return .burpeeBroadJumps
        // 런지는 대회와 같은 100 m 지만 PFT 는 무게를 지지 않는다. 종목 자체는 같으므로
        // 표준 스테이션으로 두고, 무게만 비워서 화면과 기록이 대회 런지와 이어지게 한다.
        case .lunges: return .sandbagLunges
        case .row: return .rowing
        case .pushUps: return nil
        case .wallBalls: return .wallBalls
        }
    }

    /// 실제 세그먼트에 들어갈 종목. 커스텀 종목은 이름을 받아서 만든다.
    public func stationKind(customName: String) -> StationKind? {
        guard segmentType == .station else { return nil }
        return standardStation ?? .custom(name: customName)
    }

    public var target: StationTarget {
        switch self {
        case .run: return .distance(meters: 1000)
        case .burpeeBroadJumps: return .reps(count: 50)
        case .lunges: return .distance(meters: 100)
        case .row: return .distance(meters: 1000)
        case .pushUps: return .reps(count: 30)
        case .wallBalls: return .reps(count: 100)
        }
    }

    /// 런 구간의 거리(m). 런이 아니면 nil.
    public var runDistanceMeters: Double? {
        guard case .distance(let meters) = target, segmentType == .run else { return nil }
        return meters
    }

    // MARK: 지역화

    public var nameLocalizationKey: String { "pft.step.\(stringsKeyComponent).name" }

    public var defaultName: String {
        switch self {
        case .run: return "Run"
        case .burpeeBroadJumps: return "Burpee Broad Jumps"
        case .lunges: return "Lunges"
        case .row: return "Row"
        case .pushUps: return "Hand-Release Push-ups"
        case .wallBalls: return "Wall Balls"
        }
    }

    private var stringsKeyComponent: String {
        switch self {
        case .run: return "run"
        case .burpeeBroadJumps: return "burpee_broad_jumps"
        case .lunges: return "lunges"
        case .row: return "row"
        case .pushUps: return "push_ups"
        case .wallBalls: return "wall_balls"
        }
    }
}

// MARK: - 벤치마크 정의

/// 공식 PFT 벤치마크의 상수와 기록 판별.
///
/// 템플릿 조립은 `HyroxPresets.pftBenchmark(...)` 가 맡고, 완료 기록에서 시간을 읽는 일은
/// 여기서 한다. `CompletedWorkout` 은 어떤 템플릿에서 나왔는지 들고 있지 않아서,
/// 세그먼트 ID 와 코스 모양 두 가지로 판별한다.
public enum PFTBenchmark {

    /// 템플릿 문구 키(이름).
    public static let nameLocalizationKey = "pft.template.name"
    public static let defaultName = "HYROX PFT"
    /// 한 줄 설명 키.
    public static let summaryLocalizationKey = "pft.template.summary"
    public static let defaultSummary =
        "The official fitness test: 1 km run, 50 burpee broad jumps, 100 m lunges, 1 km row, 30 push-ups, 100 wall balls."

    /// 구간 수 (6).
    public static var stepCount: Int { PFTStep.allCases.count }

    /// 템플릿 고정 ID.
    ///
    /// 훈련 세션과 같은 이유로 고정한다 — 요청할 때마다 새로 조립되므로 ID 가 흔들리면
    /// 같은 벤치마크가 매번 다른 템플릿으로 보인다. 마지막 두 자리는 "템플릿 자신" 슬롯이고,
    /// 세그먼트 ID 는 그 자리에 세그먼트 번호를 넣어 만든다.
    public static var templateId: UUID {
        UUID(uuidString: templateIdString) ?? UUID()
    }

    public static func segmentId(at index: Int) -> UUID {
        guard (0..<0xFF).contains(index) else { return UUID() }
        let slot = String(format: "%02X", index)
        return UUID(uuidString: String(templateIdString.dropLast(2)) + slot) ?? UUID()
    }

    public static let templateIdString = "9D2C6B10-3F84-4A57-8E41-7C0B5A9D01FF"

    // MARK: 기록 판별

    /// 이 기록이 PFT 인지 여부.
    ///
    /// 앱에서 시작한 기록은 세그먼트 ID 가 그대로 남으므로 ID 로 바로 알 수 있다.
    /// 워치·가민을 거치며 ID 가 달라진 기록을 위해 코스 모양 판별도 함께 둔다.
    /// 모양 판별은 표준 종목만 보므로 표시 이름의 언어에 흔들리지 않는다.
    public static func isRecord(_ workout: CompletedWorkout) -> Bool {
        matchesSegmentIds(workout) || matchesShape(workout)
    }

    private static func matchesSegmentIds(_ workout: CompletedWorkout) -> Bool {
        guard workout.segments.count == stepCount else { return false }
        return workout.segments.enumerated().allSatisfy { index, record in
            record.segmentId == segmentId(at: index)
        }
    }

    private static func matchesShape(_ workout: CompletedWorkout) -> Bool {
        guard workout.segments.count == stepCount else { return false }
        guard workout.segments.map(\.type) == PFTStep.allCases.map(\.segmentType) else { return false }

        let stations = workout.orderedStationKinds
        let expected = PFTStep.allCases.filter { $0.segmentType == .station }
        guard stations.count == expected.count else { return false }

        for (kind, step) in zip(stations, expected) {
            if let standard = step.standardStation {
                guard kind == standard else { return false }
            } else {
                // 커스텀 종목 자리. 이름은 언어마다 다르므로 "공식 종목이 아니다" 까지만 본다.
                guard !StationKind.standardOrder.contains(kind) else { return false }
            }
        }
        return true
    }

    /// PFT 기록의 총 소요 시간(초). PFT 가 아니면 nil.
    ///
    /// 일시정지를 뺀 실제 운동 시간을 쓴다 — 중간에 멈춘 시간까지 세면 같은 수행이
    /// 다른 등급으로 읽힌다.
    public static func totalSeconds(of workout: CompletedWorkout) -> TimeInterval? {
        guard isRecord(workout) else { return nil }
        return workout.totalActiveDuration
    }

    /// PFT 기록의 구간별 소요 시간. PFT 가 아니면 빈 값.
    public static func stepSeconds(of workout: CompletedWorkout) -> [PFTStep: TimeInterval] {
        guard isRecord(workout) else { return [:] }
        var result: [PFTStep: TimeInterval] = [:]
        for (index, step) in PFTStep.allCases.enumerated() where workout.segments.indices.contains(index) {
            result[step] = workout.segments[index].activeDuration
        }
        return result
    }

    /// 기록 목록에서 가장 최근 PFT 를 고른다.
    public static func mostRecentRecord(in workouts: [CompletedWorkout]) -> CompletedWorkout? {
        workouts.filter(isRecord).max { $0.finishedAt < $1.finishedAt }
    }
}
