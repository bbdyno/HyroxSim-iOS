//
//  ProgressAnalyzer.swift
//  HyroxCore
//
//  Created by bbdyno on 9/20/26.
//

import Foundation

/// 진척 추적이 한 줄로 다루는 구간.
///
/// 러닝 8회와 록스존 전부는 각각 하나로 묶는다. 한 회씩 쪼개면 스테이션보다 늘 작아
/// 보여서, 정작 시간을 가장 많이 잃는 곳이 눈에 띄지 않는다(`GapItem.Kind` 와 같은 이유).
public enum ProgressSegmentKind: Hashable, Sendable {
    /// 8회 러닝 합계.
    case run
    /// 록스존 전부의 합계.
    case roxZone
    /// 공식 스테이션 한 종목.
    case station(StationKind)

    /// 화면·정렬에서 쓰는 고정 순서(러닝 → 록스존 → 공식 스테이션 8개).
    public var orderIndex: Int {
        switch self {
        case .run:
            return 0
        case .roxZone:
            return 1
        case .station(let station):
            let index = StationKind.standardOrder.firstIndex(of: station)
                ?? StationKind.standardOrder.count
            return 2 + index
        }
    }
}

/// 차트 한 점. 기록 하나에서 뽑은 (날짜, 초).
public struct ProgressSeriesPoint: Identifiable, Hashable, Sendable {
    /// 원본 기록의 ID. 같은 날 두 번 뛰어도 점이 겹치지 않는다.
    public let id: UUID
    public let date: Date
    public let seconds: TimeInterval

    public init(id: UUID, date: Date, seconds: TimeInterval) {
        self.id = id
        self.date = date
        self.seconds = seconds
    }
}

/// 진척 추적이 읽어 들인 기록 하나.
///
/// 원본 `CompletedWorkout` 이 아니라 "비교할 수 있는 형태로 정리된" 값이다. 여기 들어온
/// 기록은 이미 손상 검사와 표준 코스 검사를 통과했으므로, 화면은 다시 검사하지 않는다.
public struct ProgressRecord: Identifiable, Hashable, Sendable {

    public let id: UUID
    public let finishedAt: Date
    public let templateName: String
    public let division: HyroxDivision

    /// 구간 활성 시간의 합(일시정지 제외).
    ///
    /// 벽시계 시간(`totalDuration`)이 아니라 구간 합을 쓴다. 구간별 추세와 총시간 추세가
    /// 같은 기준이어야 "어디서 줄었는지"가 총시간 변화와 맞아떨어진다.
    public let totalSeconds: TimeInterval
    public let runSeconds: TimeInterval
    public let roxZoneSeconds: TimeInterval
    public let stationSeconds: [StationKind: TimeInterval]

    /// 러닝 구간 기록을 수행 순서대로. 표준 코스라면 8개.
    public let runSplits: [TimeInterval]
    /// 첫 러닝 페이스(초/km). 계획 거리를 모르면 nil.
    public let firstRunPaceSecondsPerKm: Double?
    /// 러닝 저하율 = 마지막 런 ÷ 첫 런. 1.0 이면 처음과 끝이 같은 속도다.
    public let runFadeRatio: Double?
    /// 이 완주 시간의 퍼센타일(낮을수록 빠름). 참조 데이터가 없으면 nil.
    public let percentile: Double?
    /// 록스존을 따로 기록한 코스인지.
    public let usesRoxZone: Bool

    public var firstRunSeconds: TimeInterval? { runSplits.first }
    public var lastRunSeconds: TimeInterval? { runSplits.last }

    public func seconds(for kind: ProgressSegmentKind) -> TimeInterval? {
        switch kind {
        case .run: return runSeconds
        case .roxZone: return usesRoxZone ? roxZoneSeconds : nil
        case .station(let station): return stationSeconds[station]
        }
    }
}

/// 한 구간이 첫 기록에서 최근 기록까지 어떻게 움직였는지.
public struct ProgressSegmentTrend: Identifiable, Hashable, Sendable {

    public let kind: ProgressSegmentKind
    /// 가장 오래된 기록의 값(초).
    public let earliestSeconds: TimeInterval
    /// 가장 최근 기록의 값(초).
    public let latestSeconds: TimeInterval
    /// 지금까지의 최고 기록(초).
    public let bestSeconds: TimeInterval

    /// 최근 − 최초(초). 음수면 그만큼 빨라졌다.
    public var deltaSeconds: TimeInterval { latestSeconds - earliestSeconds }
    public var isImproving: Bool { deltaSeconds < 0 }

    public var id: ProgressSegmentKind { kind }

    public init(
        kind: ProgressSegmentKind,
        earliestSeconds: TimeInterval,
        latestSeconds: TimeInterval,
        bestSeconds: TimeInterval
    ) {
        self.kind = kind
        self.earliestSeconds = earliestSeconds
        self.latestSeconds = latestSeconds
        self.bestSeconds = bestSeconds
    }
}

/// 저장된 기록 전체를 시간순으로 정리한 결과.
public struct ProgressReport: Hashable, Sendable {

    /// 비교 기준이 된 디비전. 읽을 수 있는 기록이 하나도 없으면 nil.
    public let division: HyroxDivision?
    /// 오래된 → 최근 순.
    public let records: [ProgressRecord]
    /// 구간별 추세. 최근 기록에서 오래 걸린 순.
    public let segmentTrends: [ProgressSegmentTrend]
    /// 숫자를 믿을 수 없어 건너뛴 기록 수.
    public let skippedCorruptCount: Int
    /// 표준 코스가 아니거나 디비전이 달라 같이 비교할 수 없어 뺀 기록 수.
    public let skippedIncompatibleCount: Int

    public init(
        division: HyroxDivision?,
        records: [ProgressRecord],
        segmentTrends: [ProgressSegmentTrend],
        skippedCorruptCount: Int,
        skippedIncompatibleCount: Int
    ) {
        self.division = division
        self.records = records
        self.segmentTrends = segmentTrends
        self.skippedCorruptCount = skippedCorruptCount
        self.skippedIncompatibleCount = skippedIncompatibleCount
    }

    /// 아직 아무것도 읽지 않은 상태.
    public static let empty = ProgressReport(
        division: nil,
        records: [],
        segmentTrends: [],
        skippedCorruptCount: 0,
        skippedIncompatibleCount: 0
    )

    /// 추세를 말할 수 있을 만큼 기록이 쌓였는지. 한 건으로는 "변화"가 없다.
    public var hasEnoughRecords: Bool { records.count >= ProgressAnalyzer.minimumRecordCount }

    public var earliest: ProgressRecord? { records.first }
    public var latest: ProgressRecord? { records.last }
    /// 가장 빨랐던 기록.
    public var fastest: ProgressRecord? { records.min { $0.totalSeconds < $1.totalSeconds } }

    /// 최근 − 최초 완주 시간(초). 음수면 빨라졌다.
    public var totalDeltaSeconds: TimeInterval? {
        guard hasEnoughRecords, let earliest, let latest else { return nil }
        return latest.totalSeconds - earliest.totalSeconds
    }

    /// 최근 − 최초 퍼센타일. 음수면 순위가 올라갔다(퍼센타일은 낮을수록 빠름).
    public var percentileDelta: Double? {
        guard hasEnoughRecords,
              let first = records.first(where: { $0.percentile != nil })?.percentile,
              let last = records.last(where: { $0.percentile != nil })?.percentile,
              records.filter({ $0.percentile != nil }).count >= ProgressAnalyzer.minimumRecordCount
        else { return nil }
        return last - first
    }

    /// 스테이션과 록스존만. 러닝 합계(≈총시간의 절반)를 빼야 나머지가 한 차트에서 보인다.
    public var stationTrends: [ProgressSegmentTrend] {
        segmentTrends.filter { $0.kind != .run }
    }

    public func series(for kind: ProgressSegmentKind) -> [ProgressSeriesPoint] {
        records.compactMap { record in
            guard let seconds = record.seconds(for: kind) else { return nil }
            return ProgressSeriesPoint(id: record.id, date: record.finishedAt, seconds: seconds)
        }
    }

    /// 완주 시간 추세.
    public var totalSeries: [ProgressSeriesPoint] {
        records.map {
            ProgressSeriesPoint(id: $0.id, date: $0.finishedAt, seconds: $0.totalSeconds)
        }
    }
}

/// 완료된 기록들을 시간순으로 읽어 "무엇이 나아졌고 무엇이 그대로인지" 계산한다.
///
/// 순수 함수다. 입력은 기록 목록과 참조 데이터뿐이고 시계도 저장소도 읽지 않는다.
/// 참조 데이터는 v4 퍼센타일 표(`PaceDataProviding`)를 먼저 쓰고, 없으면 v3 버킷
/// (`PacePlanner`)으로 떨어진다. 둘 다 없으면 퍼센타일만 비고 나머지는 그대로 나온다.
public struct ProgressAnalyzer: Sendable {

    /// 추세를 그리기 위한 최소 기록 수.
    public static let minimumRecordCount = 2

    /// 이보다 긴 기록은 숫자를 믿지 않는다. 가장 느린 공식 기록도 4시간을 넘지 않고,
    /// 종료 신호를 놓친 채 밤새 열려 있던 세션이 실제로 이 모양으로 저장된 적이 있다.
    public static let maximumPlausibleTotalSeconds: TimeInterval = 12 * 60 * 60

    /// 첫 러닝 페이스를 계산할 때 쓰는 기본 거리. 공식 코스의 한 랩.
    public static let standardRunDistanceMeters: Double = 1000

    private let paceData: (any PaceDataProviding)?
    private let fallbackPlanner: PacePlanner?

    /// - Parameters:
    ///   - paceData: v4 퍼센타일 표. 앱에서는 `AppServices.paceData` 가 준다.
    ///   - fallbackPlanner: v4 를 못 읽을 때 쓸 v3 버킷.
    public init(
        paceData: (any PaceDataProviding)? = nil,
        fallbackPlanner: PacePlanner? = nil
    ) {
        self.paceData = paceData
        self.fallbackPlanner = fallbackPlanner
    }

    /// 기록들을 시간순으로 정리한다.
    ///
    /// - Parameters:
    ///   - workouts: 저장된 기록. 순서는 상관없다.
    ///   - division: 비교할 디비전. 생략하면 가장 최근에 읽을 수 있었던 기록의 디비전을 쓴다.
    ///     디비전을 섞으면 무게도 횟수도 다른 경기를 같은 선으로 잇게 된다.
    public func analyze(
        _ workouts: [CompletedWorkout],
        division: HyroxDivision? = nil
    ) -> ProgressReport {

        var corrupt = 0
        var incompatible = 0
        var readable: [CompletedWorkout] = []

        for workout in workouts {
            guard Self.isReadable(workout) else {
                corrupt += 1
                continue
            }
            guard workout.division != nil, workout.isStandardHyroxCourse else {
                incompatible += 1
                continue
            }
            readable.append(workout)
        }

        let sorted = readable.sorted { $0.finishedAt < $1.finishedAt }
        guard let targetDivision = division ?? sorted.last?.division else {
            return ProgressReport(
                division: nil,
                records: [],
                segmentTrends: [],
                skippedCorruptCount: corrupt,
                skippedIncompatibleCount: incompatible
            )
        }

        var records: [ProgressRecord] = []
        for workout in sorted {
            guard workout.division == targetDivision else {
                incompatible += 1
                continue
            }
            guard let record = makeRecord(workout, division: targetDivision) else {
                // 표준 코스 검사를 통과했는데 스테이션을 못 읽는 경우다 — 숫자를 지어내는
                // 대신 손상으로 센다.
                corrupt += 1
                continue
            }
            records.append(record)
        }

        return ProgressReport(
            division: targetDivision,
            records: records,
            segmentTrends: Self.trends(from: records),
            skippedCorruptCount: corrupt,
            skippedIncompatibleCount: incompatible
        )
    }

    // MARK: - Record

    private func makeRecord(
        _ workout: CompletedWorkout,
        division: HyroxDivision
    ) -> ProgressRecord? {

        let stationKinds = workout.orderedStationKinds
        let stationRecords = workout.stationSegments
        guard stationKinds.count == stationRecords.count else { return nil }

        var stationSeconds: [StationKind: TimeInterval] = [:]
        for (kind, record) in zip(stationKinds, stationRecords) {
            // 같은 종목이 두 번 나오는 코스는 표준이 아니므로 여기 오지 않는다.
            stationSeconds[kind] = record.activeDuration
        }
        guard stationSeconds.count == stationRecords.count else { return nil }

        let runRecords = workout.runSegments
        let runSplits = runRecords.map(\.activeDuration)
        let roxSegments = workout.roxZoneSegments
        let totalSeconds = workout.totalActiveDuration

        let firstRunDistance = runRecords.first?.plannedDistanceMeters
            ?? Self.standardRunDistanceMeters
        let firstRunPace: Double? = {
            guard let first = runSplits.first, firstRunDistance > 0 else { return nil }
            return first / (firstRunDistance / 1000)
        }()

        let fade: Double? = {
            guard runSplits.count >= 2, let first = runSplits.first, let last = runSplits.last,
                  first > 0 else { return nil }
            return last / first
        }()

        return ProgressRecord(
            id: workout.id,
            finishedAt: workout.finishedAt,
            templateName: workout.templateName,
            division: division,
            totalSeconds: totalSeconds,
            runSeconds: runSplits.reduce(0, +),
            roxZoneSeconds: roxSegments.reduce(0) { $0 + $1.activeDuration },
            stationSeconds: stationSeconds,
            runSplits: runSplits,
            firstRunPaceSecondsPerKm: firstRunPace,
            runFadeRatio: fade,
            percentile: percentile(forTotalSeconds: totalSeconds, division: division),
            usesRoxZone: !roxSegments.isEmpty
        )
    }

    // MARK: - Percentile

    /// v4 표를 먼저 읽고, 없으면 v3 버킷으로 떨어진다.
    private func percentile(
        forTotalSeconds seconds: TimeInterval,
        division: HyroxDivision
    ) -> Double? {
        guard seconds.isFinite, seconds > 0 else { return nil }

        if let provider = paceData, let dataset = try? provider.dataset(for: division) {
            return dataset.percentile(forGoalSeconds: Int(seconds.rounded()))
        }
        if let bucket = fallbackPlanner?.interpolate(
            targetMinutes: seconds / 60,
            division: division
        ) {
            return bucket.percentile
        }
        return nil
    }

    // MARK: - Trends

    static func trends(from records: [ProgressRecord]) -> [ProgressSegmentTrend] {
        guard let earliest = records.first, let latest = records.last,
              records.count >= minimumRecordCount else { return [] }

        var kinds: [ProgressSegmentKind] = [.run]
        if records.allSatisfy(\.usesRoxZone) { kinds.append(.roxZone) }
        kinds.append(contentsOf: StationKind.standardOrder.map(ProgressSegmentKind.station))

        return kinds.compactMap { kind -> ProgressSegmentTrend? in
            guard let first = earliest.seconds(for: kind),
                  let last = latest.seconds(for: kind) else { return nil }
            let best = records.compactMap { $0.seconds(for: kind) }.min() ?? min(first, last)
            return ProgressSegmentTrend(
                kind: kind,
                earliestSeconds: first,
                latestSeconds: last,
                bestSeconds: best
            )
        }
        .sorted { lhs, rhs in
            if lhs.latestSeconds != rhs.latestSeconds {
                // 시간을 가장 많이 쓰는 구간이 위로. 월볼·버피·런지가 여기 올라온다.
                return lhs.latestSeconds > rhs.latestSeconds
            }
            return lhs.kind.orderIndex < rhs.kind.orderIndex
        }
    }

    // MARK: - Validation

    /// 숫자를 믿을 수 있는 기록인지.
    ///
    /// 워치가 죽은 뒤 복구된 기록, 종료 신호를 놓친 세션, 마이그레이션이 덜 된 행에서
    /// 음수·NaN·며칠짜리 구간이 실제로 나온다. 한 건이 그렇다고 화면 전체를 비우는 대신
    /// 그 건만 빼고 몇 건을 뺐는지 알려 준다.
    static func isReadable(_ workout: CompletedWorkout) -> Bool {
        guard !workout.segments.isEmpty else { return false }
        guard workout.finishedAt >= workout.startedAt else { return false }

        for segment in workout.segments {
            let duration = segment.activeDuration
            guard duration.isFinite, duration >= 0 else { return false }
        }

        let total = workout.totalActiveDuration
        guard total.isFinite, total > 0, total <= maximumPlausibleTotalSeconds else { return false }
        return true
    }
}
