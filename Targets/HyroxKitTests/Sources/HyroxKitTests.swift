//
//  HyroxKitTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class HyroxKitTests: XCTestCase {
    func testVersion() throws {
        XCTAssertEqual(HyroxKit.version, "0.1.0")
    }
}

// MARK: - Gap Analysis

/// 고정된 기준 기록을 돌려주는 테스트용 데이터 소스.
/// 번들 데이터가 갱신돼도 분석 로직 테스트가 흔들리지 않게 한다.
private struct StubGapReferenceProvider: GapReferenceProviding {
    var runSeconds: TimeInterval = 8 * 300
    var roxZoneSeconds: TimeInterval = 15 * 30
    var stationSeconds: TimeInterval = 240
    var percentile: Double? = 25
    var isExtrapolated = false
    /// nil 을 돌려주는 상황(데이터 없음)을 재현할 때 false 로 둔다.
    var hasData = true

    func reference(for target: GapTarget, division: HyroxDivision) -> GapReference? {
        guard hasData else { return nil }

        var stations: [StationKind: TimeInterval] = [:]
        for kind in StationKind.standardOrder {
            stations[kind] = stationSeconds
        }

        return GapReference(
            totalSeconds: runSeconds + roxZoneSeconds + stationSeconds * 8,
            runSeconds: runSeconds,
            roxZoneSeconds: roxZoneSeconds,
            stationSeconds: stations,
            percentile: percentile,
            isExtrapolated: isExtrapolated
        )
    }
}

final class GapAnalyzerTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: - Fixtures

    /// 공식 코스(8 × [러닝 · 록스존 · 스테이션 · 록스존], 마지막 퇴장 록스존 없음) 기록.
    private func makeStandardWorkout(
        division: HyroxDivision? = .menOpenSingle,
        runSeconds: TimeInterval = 300,
        roxSeconds: TimeInterval = 30,
        stationSeconds: TimeInterval = 240,
        stationOverrides: [StationKind: TimeInterval] = [:],
        includeRoxZones: Bool = true,
        goalSecondsPerSegment: TimeInterval? = nil,
        runDistanceMeters: Double? = 1000
    ) -> CompletedWorkout {
        var records: [SegmentRecord] = []
        var cursor = start
        var index = 0

        func append(_ type: SegmentType, duration: TimeInterval, station: StationKind? = nil) {
            records.append(
                SegmentRecord(
                    segmentId: UUID(),
                    index: index,
                    type: type,
                    startedAt: cursor,
                    endedAt: cursor.addingTimeInterval(duration),
                    stationDisplayName: station?.displayName,
                    plannedDistanceMeters: type == .run ? runDistanceMeters : nil,
                    goalDurationSeconds: goalSecondsPerSegment
                )
            )
            cursor = cursor.addingTimeInterval(duration)
            index += 1
        }

        for (stationIndex, kind) in StationKind.standardOrder.enumerated() {
            append(.run, duration: runSeconds)
            if includeRoxZones {
                append(.roxZone, duration: roxSeconds)
            }
            append(.station, duration: stationOverrides[kind] ?? stationSeconds, station: kind)
            if includeRoxZones, stationIndex < StationKind.standardOrder.count - 1 {
                append(.roxZone, duration: roxSeconds)
            }
        }

        return CompletedWorkout(
            templateName: "Race Simulation",
            division: division,
            startedAt: start,
            finishedAt: cursor,
            segments: records
        )
    }

    private func makeCustomWorkout() -> CompletedWorkout {
        CompletedWorkout(
            templateName: "Half Rox",
            division: .menOpenSingle,
            startedAt: start,
            finishedAt: start.addingTimeInterval(600),
            segments: [
                SegmentRecord(
                    segmentId: UUID(),
                    index: 0,
                    type: .run,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(300),
                    plannedDistanceMeters: 500
                ),
                SegmentRecord(
                    segmentId: UUID(),
                    index: 1,
                    type: .station,
                    startedAt: start.addingTimeInterval(300),
                    endedAt: start.addingTimeInterval(600),
                    stationDisplayName: StationKind.skiErg.displayName
                )
            ]
        )
    }

    // MARK: - 표준 코스 판정

    func testStandardCourseIsRecognized() {
        XCTAssertTrue(makeStandardWorkout().isStandardHyroxCourse)
        XCTAssertTrue(makeStandardWorkout(includeRoxZones: false).isStandardHyroxCourse)
    }

    func testCustomCourseReturnsNoAnalysis() {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeCustomWorkout()

        XCTAssertFalse(workout.isStandardHyroxCourse)
        XCTAssertNil(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))
    }

    func testRunDistanceOtherThanOneKilometerIsNotStandard() {
        let workout = makeStandardWorkout(runDistanceMeters: 500)
        XCTAssertFalse(workout.isStandardHyroxCourse)
        XCTAssertNil(
            GapAnalyzer(referenceProvider: StubGapReferenceProvider())
                .analyze(workout, target: .finishTime(seconds: 5_400))
        )
    }

    func testMissingDivisionReturnsNoAnalysis() {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeStandardWorkout(division: nil)

        XCTAssertNil(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))
        // 디비전을 직접 넘기면 분석할 수 있다.
        XCTAssertNotNil(analyzer.analyze(workout, target: .finishTime(seconds: 5_400), division: .menOpenSingle))
    }

    func testMissingReferenceDataReturnsNoAnalysis() {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider(hasData: false))
        XCTAssertNil(analyzer.analyze(makeStandardWorkout(), target: .finishTime(seconds: 5_400)))
    }

    // MARK: - 묶음과 정렬

    func testRunsAndRoxZonesAreGroupedIntoOneItemEach() throws {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeStandardWorkout(runSeconds: 320, roxSeconds: 40, stationSeconds: 240)
        let analysis = try XCTUnwrap(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))

        // 러닝 8개 + 록스존 15개가 각각 한 줄로 접힌다 → 러닝 1 + 록스존 1 + 스테이션 8
        XCTAssertEqual(analysis.items.count, 10)
        XCTAssertEqual(analysis.items.filter { $0.kind == .run }.count, 1)
        XCTAssertEqual(analysis.items.filter { $0.kind == .roxZone }.count, 1)

        let run = try XCTUnwrap(analysis.items.first { $0.kind == .run })
        XCTAssertEqual(run.actualSeconds, 8 * 320, accuracy: 0.001)
        XCTAssertEqual(run.referenceSeconds, 8 * 300, accuracy: 0.001)
        XCTAssertEqual(run.deltaSeconds, 160, accuracy: 0.001)

        let rox = try XCTUnwrap(analysis.items.first { $0.kind == .roxZone })
        XCTAssertEqual(rox.actualSeconds, 15 * 40, accuracy: 0.001)
        XCTAssertEqual(rox.referenceSeconds, 15 * 30, accuracy: 0.001)
    }

    func testCourseWithoutRoxZonesFoldsTransitionTimeIntoRunReference() throws {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeStandardWorkout(runSeconds: 330, includeRoxZones: false)
        let analysis = try XCTUnwrap(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))

        XCTAssertEqual(analysis.items.count, 9)
        XCTAssertNil(analysis.items.first { $0.kind == .roxZone })

        let run = try XCTUnwrap(analysis.items.first { $0.kind == .run })
        // 록스존이 없으면 전환 시간이 러닝 기록에 섞여 있으므로 기준도 합쳐서 본다.
        XCTAssertEqual(run.referenceSeconds, 8 * 300 + 15 * 30, accuracy: 0.001)
    }

    func testItemsAreSortedByGapDescending() throws {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeStandardWorkout(
            runSeconds: 305,          // +40 전체
            roxSeconds: 30,           // 격차 없음
            stationSeconds: 240,
            stationOverrides: [
                .wallBalls: 420,      // +180
                .rowing: 300          // +60
            ]
        )
        let analysis = try XCTUnwrap(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))

        XCTAssertEqual(
            analysis.behindItems.map(\.kind),
            [.station(.wallBalls), .station(.rowing), .run]
        )
        let deltas = analysis.items.map(\.deltaSeconds)
        XCTAssertEqual(deltas, deltas.sorted(by: >))
    }

    func testSharesAreRelativeToTotalLoss() throws {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeStandardWorkout(
            runSeconds: 300,
            roxSeconds: 30,
            stationSeconds: 240,
            stationOverrides: [
                .wallBalls: 300,  // +60
                .rowing: 260      // +20
            ]
        )
        let analysis = try XCTUnwrap(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))

        let wallBalls = try XCTUnwrap(analysis.items.first { $0.kind == .station(.wallBalls) })
        let rowing = try XCTUnwrap(analysis.items.first { $0.kind == .station(.rowing) })
        XCTAssertEqual(wallBalls.share, 0.75, accuracy: 0.0001)
        XCTAssertEqual(rowing.share, 0.25, accuracy: 0.0001)

        // 느리지 않았던 구간은 비중 0, 전체 합은 1.
        XCTAssertEqual(analysis.items.map(\.share).reduce(0, +), 1.0, accuracy: 0.0001)
        XCTAssertEqual(analysis.recoverableSeconds, 80, accuracy: 0.001)
    }

    // MARK: - 이미 목표를 달성한 경우

    func testGoalSlowerThanRecordIsReportedAsAlreadyMet() throws {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        // 모든 구간이 기준보다 빠르다.
        let workout = makeStandardWorkout(runSeconds: 280, roxSeconds: 25, stationSeconds: 220)
        let analysis = try XCTUnwrap(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))

        XCTAssertTrue(analysis.isGoalAlreadyMet)
        XCTAssertLessThan(analysis.totalGapSeconds, 0)
        XCTAssertTrue(analysis.behindItems.isEmpty)
        XCTAssertEqual(analysis.recoverableSeconds, 0, accuracy: 0.001)
        // 분모가 0 이어도 비중 계산이 NaN 으로 새지 않는다.
        XCTAssertTrue(analysis.items.allSatisfy { $0.share == 0 })
    }

    func testGoalMetOverallStillReportsSlowSegments() throws {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeStandardWorkout(
            runSeconds: 280,       // -160 전체
            roxSeconds: 25,        // -75 전체
            stationSeconds: 220,   // -20 × 7
            stationOverrides: [.wallBalls: 260] // +20
        )
        let analysis = try XCTUnwrap(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))

        XCTAssertTrue(analysis.isGoalAlreadyMet)
        XCTAssertEqual(analysis.behindItems.map(\.kind), [.station(.wallBalls)])
        XCTAssertEqual(analysis.recoverableSeconds, 20, accuracy: 0.001)
    }

    func testTotalsAddUp() throws {
        let analyzer = GapAnalyzer(referenceProvider: StubGapReferenceProvider())
        let workout = makeStandardWorkout(runSeconds: 310, roxSeconds: 35, stationSeconds: 250)
        let analysis = try XCTUnwrap(analyzer.analyze(workout, target: .finishTime(seconds: 5_400)))

        let itemActualSum = analysis.items.reduce(0) { $0 + $1.actualSeconds }
        let itemDeltaSum = analysis.items.reduce(0) { $0 + $1.deltaSeconds }
        XCTAssertEqual(itemActualSum, analysis.actualTotalSeconds, accuracy: 0.001)
        XCTAssertEqual(itemDeltaSum, analysis.totalGapSeconds, accuracy: 0.001)
    }

    func testExtrapolatedReferenceIsFlagged() throws {
        let analyzer = GapAnalyzer(
            referenceProvider: StubGapReferenceProvider(isExtrapolated: true)
        )
        let analysis = try XCTUnwrap(
            analyzer.analyze(makeStandardWorkout(), target: .finishTime(seconds: 5_400))
        )
        XCTAssertTrue(analysis.isReferenceExtrapolated)
    }
}

// MARK: - Bundled reference data

final class PacePlannerGapReferenceProviderTests: XCTestCase {

    private var provider: PacePlannerGapReferenceProvider!

    override func setUpWithError() throws {
        provider = try PacePlannerGapReferenceProvider()
    }

    func testFinishTimeReferenceSplitsAddUpToTheTotal() throws {
        let reference = try XCTUnwrap(
            provider.reference(for: .finishTime(seconds: 5_400), division: .menOpenSingle)
        )

        let stationTotal = reference.stationSeconds.values.reduce(0, +)
        XCTAssertEqual(reference.stationSeconds.count, 8)
        XCTAssertEqual(
            reference.runSeconds + reference.roxZoneSeconds + stationTotal,
            reference.totalSeconds,
            accuracy: 1.5
        )
        XCTAssertFalse(reference.isExtrapolated)
        XCTAssertNotNil(reference.percentile)
    }

    func testFasterPercentileMeansFasterReference() throws {
        let top10 = try XCTUnwrap(provider.reference(for: .percentile(10), division: .menOpenSingle))
        let median = try XCTUnwrap(provider.reference(for: .percentile(50), division: .menOpenSingle))

        XCTAssertLessThan(top10.totalSeconds, median.totalSeconds)
        XCTAssertLessThan(top10.runSeconds, median.runSeconds)
    }

    func testGoalOutsideTheDataIsFlaggedAsExtrapolated() throws {
        // 어떤 디비전도 20분 완주 기록을 가지고 있지 않다.
        let reference = try XCTUnwrap(
            provider.reference(for: .finishTime(seconds: 1_200), division: .menOpenSingle)
        )
        XCTAssertTrue(reference.isExtrapolated)
    }

    func testInvalidTargetsReturnNil() {
        XCTAssertNil(provider.reference(for: .finishTime(seconds: 0), division: .menOpenSingle))
        XCTAssertNil(provider.reference(for: .percentile(0), division: .menOpenSingle))
        XCTAssertNil(provider.reference(for: .percentile(140), division: .menOpenSingle))
    }

    func testAnalysisRunsAgainstBundledData() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var records: [SegmentRecord] = []
        var cursor = start
        var index = 0

        func append(_ type: SegmentType, duration: TimeInterval, station: StationKind? = nil) {
            records.append(
                SegmentRecord(
                    segmentId: UUID(),
                    index: index,
                    type: type,
                    startedAt: cursor,
                    endedAt: cursor.addingTimeInterval(duration),
                    stationDisplayName: station?.displayName,
                    plannedDistanceMeters: type == .run ? 1000 : nil
                )
            )
            cursor = cursor.addingTimeInterval(duration)
            index += 1
        }

        for (stationIndex, kind) in StationKind.standardOrder.enumerated() {
            append(.run, duration: 330)
            append(.roxZone, duration: 35)
            append(.station, duration: 260, station: kind)
            if stationIndex < StationKind.standardOrder.count - 1 {
                append(.roxZone, duration: 35)
            }
        }

        let workout = CompletedWorkout(
            templateName: "Race Simulation",
            division: .menOpenSingle,
            startedAt: start,
            finishedAt: cursor,
            segments: records
        )

        let analysis = try XCTUnwrap(
            GapAnalyzer(referenceProvider: provider)
                .analyze(workout, target: .percentile(15))
        )

        XCTAssertEqual(analysis.items.count, 10)
        XCTAssertFalse(analysis.isReferenceExtrapolated)
        XCTAssertGreaterThan(analysis.totalGapSeconds, 0)
        XCTAssertEqual(
            analysis.behindItems.map(\.share).reduce(0, +),
            1.0,
            accuracy: 0.0001
        )
    }
}
