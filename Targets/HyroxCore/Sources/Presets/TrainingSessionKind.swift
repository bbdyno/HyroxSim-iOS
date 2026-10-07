//
//  TrainingSessionKind.swift
//  HyroxCore
//
//  Created by bbdyno on 9/18/26.
//

import Foundation

/// 반복 훈련용 빌트인 세션 종류.
///
/// 풀 시뮬레이션(`HyroxPresets.all`)은 대회 그 자체를 재현하는 반면, 훈련 세션은
/// 대회 준비 기간에 *여러 번* 돌릴 수 있는 짧은 구성이다. 각 세션은 기존
/// `WorkoutSegment` 조합으로만 표현되므로 워치·가민에서 프리셋과 똑같이 실행된다.
///
/// 이름/설명은 `HyroxCore` 가 번들 리소스를 갖지 않기 때문에 여기서 *키* 만 노출하고,
/// 실제 문구는 앱 타겟(`HyroxSim`)의 `Localizable.strings` 가 갖는다.
/// 지역화가 없는 호출자(테스트·가민 등)를 위해 영문 기본값도 함께 둔다.
public enum TrainingSessionKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// 피로 상태 러닝. 1 km 런 + 스테이션 1종을 반복한다.
    case compromisedRun
    /// 표준 코스의 앞 절반(런 4 + 스테이션 4).
    case halfSimulation
    /// 시간 손실이 큰 스테이션 3종 인터벌.
    case stationIntervals
    /// 록스존 전환(런 → 스테이션 진입) 드릴.
    case roxZoneDrill
    /// 월볼 100회를 내림차순 세트로 쪼갠 사다리.
    case wallBallLadder
    /// 공식 PFT(체력 테스트). 디비전 추천과 예상 완주 범위의 입력이 된다.
    case pftBenchmark

    // MARK: - 지역화

    /// `Localizable.strings` 의 세션 이름 키.
    public var nameLocalizationKey: String { "training_session.\(stringsKeyComponent).name" }

    /// `Localizable.strings` 의 세션 한 줄 설명 키.
    public var summaryLocalizationKey: String { "training_session.\(stringsKeyComponent).summary" }

    /// 지역화 문구를 못 찾았을 때 쓰는 영문 이름.
    public var defaultName: String {
        switch self {
        case .compromisedRun: return "Compromised Run"
        case .halfSimulation: return "Half Simulation"
        case .stationIntervals: return "Station Intervals"
        case .roxZoneDrill: return "ROX Zone Drill"
        case .wallBallLadder: return "Wall Ball Ladder"
        case .pftBenchmark: return "Physical Fitness Test"
        }
    }

    /// 지역화 문구를 못 찾았을 때 쓰는 영문 설명.
    public var defaultSummary: String {
        switch self {
        case .compromisedRun:
            return "1 km run straight into lunges, four times — the run that decides your race."
        case .halfSimulation:
            return "Runs 1–4 with the first four stations, at full race volume."
        case .stationIntervals:
            return "Three rounds of the stations that cost the most time."
        case .roxZoneDrill:
            return "Short run, ROX Zone, station entry — repeated until transitions are automatic."
        case .wallBallLadder:
            return "Race-volume wall balls broken into a descending ladder."
        case .pftBenchmark:
            return "The official six-part fitness test — a benchmark you can repeat every few weeks."
        }
    }

    /// 세션 템플릿의 고정 ID.
    ///
    /// 세션은 (프리셋과 달리) 요청할 때마다 새로 조립되므로, ID 를 고정해 두지 않으면
    /// 같은 세션이 매번 다른 템플릿으로 보인다. 가민/워치 동기화와 화면 diff 가
    /// 안정적으로 동작하려면 실행 간에도 같은 값이어야 한다.
    ///
    /// 마지막 두 자리(`FF`)는 "템플릿 자신" 슬롯이다. 같은 세션의 세그먼트 ID 는
    /// 그 자리에 세그먼트 번호(`00`~`FE`)를 넣어 만든다 — `WorkoutSegment` 참고.
    public var templateId: UUID {
        UUID(uuidString: templateIdString) ?? UUID()
    }

    /// 세션 안 `index` 번째 세그먼트의 고정 ID.
    /// 세그먼트가 255개를 넘으면(있을 수 없지만) 안전하게 임의 ID 로 떨어진다.
    public func segmentId(at index: Int) -> UUID {
        guard (0..<0xFF).contains(index) else { return UUID() }
        let slot = String(format: "%02X", index)
        return UUID(uuidString: String(templateIdString.dropLast(2)) + slot) ?? UUID()
    }

    // MARK: - Private

    private var stringsKeyComponent: String {
        switch self {
        case .compromisedRun: return "compromised_run"
        case .halfSimulation: return "half_simulation"
        case .stationIntervals: return "station_intervals"
        case .roxZoneDrill: return "roxzone_drill"
        case .wallBallLadder: return "wall_ball_ladder"
        case .pftBenchmark: return "pft_benchmark"
        }
    }

    /// `…-5E7A1D3F<세션 번호><슬롯>` 형태. 세션마다 번호가 달라 세그먼트 ID 도 겹치지 않는다.
    private var templateIdString: String {
        switch self {
        case .compromisedRun: return "4B1F0C4E-7A6D-4E1B-9C20-5E7A1D3F01FF"
        case .halfSimulation: return "4B1F0C4E-7A6D-4E1B-9C20-5E7A1D3F02FF"
        case .stationIntervals: return "4B1F0C4E-7A6D-4E1B-9C20-5E7A1D3F03FF"
        case .roxZoneDrill: return "4B1F0C4E-7A6D-4E1B-9C20-5E7A1D3F04FF"
        case .wallBallLadder: return "4B1F0C4E-7A6D-4E1B-9C20-5E7A1D3F05FF"
        // PFT 는 전용 프리셋(HyroxBenchmarkPresets)이 만든다. 같은 템플릿을 가리켜야
        // 홈 목록과 기록 판별(세그먼트 ID)이 어긋나지 않는다.
        case .pftBenchmark: return PFTBenchmark.templateIdString
        }
    }
}
