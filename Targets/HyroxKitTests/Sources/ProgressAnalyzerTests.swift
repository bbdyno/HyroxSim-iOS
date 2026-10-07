//
//  ProgressAnalyzerTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 9/20/26.
//

import XCTest
@testable import HyroxCore

final class ProgressAnalyzerTests: XCTestCase {

    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let day: TimeInterval = 24 * 60 * 60

    // MARK: - Fixtures

    /// 공식 코스(8 × [러닝 · 록스존 · 스테이션 · 록스존], 마지막 퇴장 록스존 없음) 기록.
    private func makeWorkout(
        daysAfterStart: Double = 0,
        division: HyroxDivision? = .menOpenSingle,
        runSeconds: TimeInterval = 300,
        lastRunSeconds: TimeInterval? = nil,
        roxSeconds: TimeInterval = 30,
        stationSeconds: TimeInterval = 240,
        stationOverrides: [StationKind: TimeInterval] = [:],
        includeRoxZones: Bool = true,
        runDistanceMeters: Double? = 1000
    ) -> CompletedWorkout {
        var records: [SegmentRecord] = []
        var cursor = start.addingTimeInterval(daysAfterStart * day)
        let began = cursor
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
                    plannedDistanceMeters: type == .run ? runDistanceMeters : nil
                )
            )
            cursor = cursor.addingTimeInterval(duration)
            index += 1
        }

        for (stationIndex, kind) in StationKind.standardOrder.enumerated() {
            let isLastRun = stationIndex == StationKind.standardOrder.count - 1
            append(.run, duration: isLastRun ? (lastRunSeconds ?? runSeconds) : runSeconds)
            if includeRoxZones { append(.roxZone, duration: roxSeconds) }
            append(.station, duration: stationOverrides[kind] ?? stationSeconds, station: kind)
            if includeRoxZones, !isLastRun { append(.roxZone, duration: roxSeconds) }
        }

        return CompletedWorkout(
            templateName: "Race Simulation",
            division: division,
            startedAt: began,
            finishedAt: cursor,
            segments: records
        )
    }

    /// 한 구간의 길이를 직접 조작한 기록. 손상 케이스를 만들 때 쓴다.
    private func makeWorkout(
        breakingSegmentAt index: Int,
        with duration: TimeInterval
    ) -> CompletedWorkout {
        let workout = makeWorkout()
        var segments = workout.segments
        let original = segments[index]
        segments[index] = SegmentRecord(
            id: original.id,
            segmentId: original.segmentId,
            index: original.index,
            type: original.type,
            startedAt: original.startedAt,
            endedAt: original.startedAt.addingTimeInterval(duration),
            stationDisplayName: original.stationDisplayName,
            plannedDistanceMeters: original.plannedDistanceMeters
        )
        return CompletedWorkout(
            id: workout.id,
            templateName: workout.templateName,
            division: workout.division,
            startedAt: workout.startedAt,
            finishedAt: workout.finishedAt,
            segments: segments
        )
    }

    private func makeCustomCourse() -> CompletedWorkout {
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

    private func makeAnalyzer(withReferenceData: Bool = true) throws -> ProgressAnalyzer {
        var planner: PacePlanner?
        if withReferenceData {
            planner = try PaceReferenceLoader.loadPacePlanner()
        }
        return ProgressAnalyzer(paceData: nil, fallbackPlanner: planner)
    }

    // MARK: - 기록 0/1/다수

    func testNoRecordsProducesAnEmptyReport() throws {
        let report = try makeAnalyzer().analyze([])

        XCTAssertNil(report.division)
        XCTAssertTrue(report.records.isEmpty)
        XCTAssertTrue(report.segmentTrends.isEmpty)
        XCTAssertFalse(report.hasEnoughRecords)
        XCTAssertNil(report.totalDeltaSeconds)
    }

    func testASingleRecordIsReadButHasNoTrendYet() throws {
        let report = try makeAnalyzer().analyze([makeWorkout()])

        XCTAssertEqual(report.records.count, 1)
        XCTAssertEqual(report.division, .menOpenSingle)
        XCTAssertFalse(report.hasEnoughRecords)
        XCTAssertTrue(report.segmentTrends.isEmpty)
        XCTAssertNil(report.totalDeltaSeconds)
        XCTAssertNil(report.percentileDelta)
    }

    func testRecordsComeBackOldestFirstRegardlessOfInputOrder() throws {
        let newest = makeWorkout(daysAfterStart: 30, runSeconds: 280)
        let oldest = makeWorkout(daysAfterStart: 0, runSeconds: 320)
        let middle = makeWorkout(daysAfterStart: 10, runSeconds: 300)

        let report = try makeAnalyzer().analyze([newest, oldest, middle])

        XCTAssertEqual(report.records.map(\.id), [oldest.id, middle.id, newest.id])
        XCTAssertEqual(report.earliest?.id, oldest.id)
        XCTAssertEqual(report.latest?.id, newest.id)
        XCTAssertEqual(report.fastest?.id, newest.id)
        XCTAssertTrue(report.hasEnoughRecords)
    }

    func testFinishTimeTrendIsTheSumOfSegments() throws {
        let oldest = makeWorkout(daysAfterStart: 0, runSeconds: 320)
        let newest = makeWorkout(daysAfterStart: 7, runSeconds: 300)

        let report = try makeAnalyzer().analyze([oldest, newest])

        // 8회 러닝에서 회당 20초씩 줄었다.
        XCTAssertEqual(report.totalDeltaSeconds, -160)
        XCTAssertEqual(report.totalSeries.count, 2)
        XCTAssertEqual(report.totalSeries.first?.seconds, oldest.totalActiveDuration)
    }

    // MARK: - 저하율 · 첫 런

    func testRunFadeRatioIsLastRunOverFirstRun() throws {
        let workout = makeWorkout(runSeconds: 300, lastRunSeconds: 360)
        let report = try makeAnalyzer().analyze([workout, makeWorkout(daysAfterStart: 7)])

        let record = try XCTUnwrap(report.earliest)
        XCTAssertEqual(record.runSplits.count, 8)
        XCTAssertEqual(record.firstRunSeconds, 300)
        XCTAssertEqual(record.lastRunSeconds, 360)
        XCTAssertEqual(try XCTUnwrap(record.runFadeRatio), 1.2, accuracy: 0.0001)
    }

    func testFirstRunPaceIsPerKilometreOfThePlannedLap() throws {
        let report = try makeAnalyzer().analyze([
            makeWorkout(daysAfterStart: 0, runSeconds: 320),
            makeWorkout(daysAfterStart: 7, runSeconds: 300)
        ])

        // 공식 코스는 1 km 랩이므로 첫 런 시간이 곧 km 당 페이스다.
        XCTAssertEqual(try XCTUnwrap(report.earliest?.firstRunPaceSecondsPerKm), 320, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(report.latest?.firstRunPaceSecondsPerKm), 300, accuracy: 0.001)
    }

    // MARK: - 구간별 추세

    func testSegmentTrendsRankTheBiggestTimeSinksFirst() throws {
        let overrides: [StationKind: TimeInterval] = [
            .wallBalls: 400,
            .sandbagLunges: 330,
            .burpeeBroadJumps: 300
        ]
        // 록스존 합계(20초 × 15)가 월볼·런지보다 아래에 오도록 잡은 값이다.
        let oldest = makeWorkout(daysAfterStart: 0, roxSeconds: 20, stationOverrides: overrides)
        let newest = makeWorkout(
            daysAfterStart: 14,
            roxSeconds: 20,
            stationOverrides: overrides.mapValues { $0 - 20 }
        )

        let report = try makeAnalyzer().analyze([oldest, newest])
        let ranked = report.stationTrends

        XCTAssertEqual(ranked.first?.kind, .station(.wallBalls))
        XCTAssertEqual(ranked.dropFirst().first?.kind, .station(.sandbagLunges))
        XCTAssertEqual(ranked.first?.deltaSeconds, -20)
        XCTAssertTrue(try XCTUnwrap(ranked.first?.isImproving))
        XCTAssertEqual(ranked.first?.bestSeconds, 380)

        // 러닝 합계는 스테이션 차트에서 빠지고 전체 목록에는 남는다.
        XCTAssertFalse(ranked.contains { $0.kind == .run })
        XCTAssertTrue(report.segmentTrends.contains { $0.kind == .run })
        XCTAssertTrue(report.segmentTrends.contains { $0.kind == .roxZone })
    }

    func testRoxZoneTotalIsTrackedAsOneLine() throws {
        let report = try makeAnalyzer().analyze([
            makeWorkout(daysAfterStart: 0, roxSeconds: 40),
            makeWorkout(daysAfterStart: 7, roxSeconds: 30)
        ])

        let rox = try XCTUnwrap(report.segmentTrends.first { $0.kind == .roxZone })
        XCTAssertEqual(rox.earliestSeconds, 40 * 15)
        XCTAssertEqual(rox.latestSeconds, 30 * 15)
        XCTAssertEqual(rox.deltaSeconds, -150)
        XCTAssertEqual(report.series(for: .roxZone).count, 2)
    }

    func testCourseWithoutRoxZonesHasNoRoxTrend() throws {
        let report = try makeAnalyzer().analyze([
            makeWorkout(daysAfterStart: 0, includeRoxZones: false),
            makeWorkout(daysAfterStart: 7, includeRoxZones: false)
        ])

        XCTAssertTrue(report.hasEnoughRecords)
        XCTAssertFalse(report.segmentTrends.contains { $0.kind == .roxZone })
        XCTAssertTrue(report.series(for: .roxZone).isEmpty)
    }

    // MARK: - 퍼센타일

    func testPercentileTrendComesFromTheReferenceData() throws {
        let fast = makeWorkout(daysAfterStart: 30, runSeconds: 240, stationSeconds: 200)
        let slow = makeWorkout(daysAfterStart: 0, runSeconds: 340, stationSeconds: 280)

        let report = try makeAnalyzer().analyze([fast, slow])

        let first = try XCTUnwrap(report.earliest?.percentile)
        let last = try XCTUnwrap(report.latest?.percentile)
        XCTAssertLessThan(last, first, "빨라졌으면 퍼센타일도 낮아져야 한다")
        XCTAssertEqual(try XCTUnwrap(report.percentileDelta), last - first, accuracy: 0.0001)
    }

    func testPercentileIsAbsentWithoutReferenceData() throws {
        let report = try makeAnalyzer(withReferenceData: false).analyze([
            makeWorkout(daysAfterStart: 0),
            makeWorkout(daysAfterStart: 7)
        ])

        XCTAssertTrue(report.hasEnoughRecords)
        XCTAssertTrue(report.records.allSatisfy { $0.percentile == nil })
        XCTAssertNil(report.percentileDelta)
    }

    func testV4DatasetIsPreferredOverTheV3Buckets() throws {
        let provider = try PaceReferenceLoader.loadBundledPaceData()
        let dataset = try provider.dataset(for: .menOpenSingle)

        let analyzer = ProgressAnalyzer(
            paceData: provider,
            fallbackPlanner: try PaceReferenceLoader.loadPacePlanner()
        )
        let workout = makeWorkout(runSeconds: 300, stationSeconds: 240)
        let report = analyzer.analyze([workout, makeWorkout(daysAfterStart: 7)])

        let record = try XCTUnwrap(report.latest)
        XCTAssertEqual(
            try XCTUnwrap(record.percentile),
            dataset.percentile(forGoalSeconds: Int(record.totalSeconds.rounded())),
            accuracy: 0.0001
        )
    }

    // MARK: - 손상 기록 · 비교 불가 기록

    func testWorkoutsWithUnusableNumbersAreSkipped() throws {
        let good = makeWorkout(daysAfterStart: 0)
        let alsoGood = makeWorkout(daysAfterStart: 7)

        let negative = makeWorkout(breakingSegmentAt: 0, with: -600)
        let notFinite = makeWorkout(breakingSegmentAt: 2, with: .infinity)
        let endless = makeWorkout(breakingSegmentAt: 4, with: 20 * 60 * 60)
        let empty = CompletedWorkout(
            templateName: "Nothing",
            division: .menOpenSingle,
            startedAt: start,
            finishedAt: start,
            segments: []
        )

        let report = try makeAnalyzer().analyze(
            [good, negative, notFinite, endless, empty, alsoGood]
        )

        XCTAssertEqual(report.records.map(\.id), [good.id, alsoGood.id])
        XCTAssertEqual(report.skippedCorruptCount, 4)
        XCTAssertEqual(report.skippedIncompatibleCount, 0)
        XCTAssertTrue(report.hasEnoughRecords)
    }

    func testCustomCoursesAndOtherDivisionsAreNotMixedIn() throws {
        let latest = makeWorkout(daysAfterStart: 20, division: .menOpenSingle)
        let older = makeWorkout(daysAfterStart: 0, division: .menOpenSingle)
        let otherDivision = makeWorkout(daysAfterStart: 10, division: .womenProSingle)
        let noDivision = makeWorkout(daysAfterStart: 5, division: nil)

        let report = try makeAnalyzer().analyze(
            [latest, older, otherDivision, noDivision, makeCustomCourse()]
        )

        XCTAssertEqual(report.division, .menOpenSingle)
        XCTAssertEqual(report.records.map(\.id), [older.id, latest.id])
        // 커스텀 코스 + 디비전 없는 기록 + 다른 디비전 = 3건
        XCTAssertEqual(report.skippedIncompatibleCount, 3)
        XCTAssertEqual(report.skippedCorruptCount, 0)
    }

    func testAnExplicitDivisionOverridesTheMostRecentRecord() throws {
        let report = try makeAnalyzer().analyze(
            [
                makeWorkout(daysAfterStart: 20, division: .menOpenSingle),
                makeWorkout(daysAfterStart: 0, division: .womenProSingle),
                makeWorkout(daysAfterStart: 10, division: .womenProSingle)
            ],
            division: .womenProSingle
        )

        XCTAssertEqual(report.division, .womenProSingle)
        XCTAssertEqual(report.records.count, 2)
        XCTAssertEqual(report.skippedIncompatibleCount, 1)
    }

    func testReadabilityRulesAreExplicit() {
        XCTAssertTrue(ProgressAnalyzer.isReadable(makeWorkout()))
        XCTAssertFalse(ProgressAnalyzer.isReadable(makeWorkout(breakingSegmentAt: 3, with: .nan)))
        XCTAssertFalse(
            ProgressAnalyzer.isReadable(
                CompletedWorkout(
                    templateName: "Backwards",
                    division: .menOpenSingle,
                    startedAt: start.addingTimeInterval(600),
                    finishedAt: start,
                    segments: makeWorkout().segments
                )
            )
        )
    }
}
