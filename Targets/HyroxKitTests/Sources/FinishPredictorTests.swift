//
//  FinishPredictorTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class FinishPredictorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// 공식 코스 기록. 총 시간이 `total` 초가 되도록 러닝에 나눈다.
    private func race(
        total: Double, daysAgo: Double, division: HyroxDivision = .menOpenSingle
    ) -> CompletedWorkout {
        let stationEach = 240.0
        let runEach = (total - stationEach * 8) / 8
        var segments: [SegmentRecord] = []
        let start = now.addingTimeInterval(-daysAgo * 86_400 - total)
        var cursor = start
        for kind in StationKind.standardOrder {
            segments.append(SegmentRecord(
                segmentId: UUID(), index: segments.count, type: .run,
                startedAt: cursor, endedAt: cursor.addingTimeInterval(runEach), plannedDistanceMeters: 1000
            ))
            cursor = cursor.addingTimeInterval(runEach)
            segments.append(SegmentRecord(
                segmentId: UUID(), index: segments.count, type: .station,
                startedAt: cursor, endedAt: cursor.addingTimeInterval(stationEach),
                stationDisplayName: kind.displayName
            ))
            cursor = cursor.addingTimeInterval(stationEach)
        }
        return CompletedWorkout(
            templateName: "HYROX", division: division, startedAt: start, finishedAt: cursor, segments: segments
        )
    }

    private func training(daysAgo: Double) -> CompletedWorkout {
        let start = now.addingTimeInterval(-daysAgo * 86_400 - 900)
        return CompletedWorkout(
            templateName: "Sled day", division: .menOpenSingle, startedAt: start,
            finishedAt: start.addingTimeInterval(900),
            segments: [SegmentRecord(
                segmentId: UUID(), index: 0, type: .station, startedAt: start,
                endedAt: start.addingTimeInterval(900), stationDisplayName: StationKind.sledPush.displayName
            )]
        )
    }

    func testNoFullRaceMeansNoPrediction() {
        XCTAssertNil(FinishPredictor.predict(from: [], division: .menOpenSingle, now: now))
        XCTAssertNil(FinishPredictor.predict(from: [training(daysAgo: 2)], division: .menOpenSingle, now: now))
    }

    func testSingleRaceIsThePrediction_withLowConfidence() throws {
        let prediction = try XCTUnwrap(
            FinishPredictor.predict(from: [race(total: 5400, daysAgo: 10)], division: .menOpenSingle, now: now)
        )
        XCTAssertEqual(prediction.seconds, 5400, accuracy: 0.001)
        XCTAssertEqual(prediction.fastestSeconds, 5400, accuracy: 0.001)
        XCTAssertEqual(prediction.slowestSeconds, 5400, accuracy: 0.001)
        XCTAssertEqual(prediction.confidence, .low)
        XCTAssertEqual(prediction.basedOn, 1)
        XCTAssertNil(prediction.trendSecondsPerWeek)
        XCTAssertNil(prediction.topPercent)
        XCTAssertNil(prediction.gapToGoalSeconds)
    }

    /// 최신 기록일수록 무겁게: (3×5100 + 2×5400 + 1×5700) / 6 = 5300.
    func testThreeRacesAreWeightedTowardTheNewest() throws {
        let workouts = [
            race(total: 5700, daysAgo: 60), race(total: 5100, daysAgo: 4), race(total: 5400, daysAgo: 32),
            training(daysAgo: 1)
        ]
        let prediction = try XCTUnwrap(FinishPredictor.predict(from: workouts, division: .menOpenSingle, now: now))

        XCTAssertEqual(prediction.seconds, 5300, accuracy: 0.001)
        XCTAssertEqual(prediction.fastestSeconds, 5100, accuracy: 0.001)
        XCTAssertEqual(prediction.slowestSeconds, 5700, accuracy: 0.001)
        XCTAssertEqual(prediction.confidence, .high)
        XCTAssertEqual(prediction.basedOn, 3)
        // 56일(8주) 동안 600초 빨라짐 → 주당 −75초.
        XCTAssertEqual(try XCTUnwrap(prediction.trendSecondsPerWeek), -75, accuracy: 0.5)
    }

    func testOnlyTheThreeNewestCount_butConfidenceReflectsAll() throws {
        let workouts = [
            race(total: 9000, daysAgo: 150), race(total: 5700, daysAgo: 60),
            race(total: 5400, daysAgo: 32), race(total: 5100, daysAgo: 4)
        ]
        let prediction = try XCTUnwrap(FinishPredictor.predict(from: workouts, division: .menOpenSingle, now: now))
        XCTAssertEqual(prediction.seconds, 5300, accuracy: 0.001)
        XCTAssertEqual(prediction.slowestSeconds, 5700, accuracy: 0.001, "the 150-day-old race is not in the range")
        XCTAssertEqual(prediction.basedOn, 3)
    }

    func testOldRacesAndOtherDivisionsAreIgnored() throws {
        let workouts = [
            race(total: 4000, daysAgo: Double(FinishPredictor.lookbackDays) + 5),
            race(total: 4200, daysAgo: 3, division: .menProSingle),
            race(total: 5600, daysAgo: 20)
        ]
        let prediction = try XCTUnwrap(FinishPredictor.predict(from: workouts, division: .menOpenSingle, now: now))
        XCTAssertEqual(prediction.seconds, 5600, accuracy: 0.001)
        XCTAssertEqual(prediction.confidence, .low)
    }

    func testTwoRacesCloseTogetherHaveNoTrend() throws {
        let workouts = [race(total: 5400, daysAgo: 3), race(total: 5500, daysAgo: 5)]
        let prediction = try XCTUnwrap(FinishPredictor.predict(from: workouts, division: .menOpenSingle, now: now))
        XCTAssertEqual(prediction.confidence, .medium)
        XCTAssertNil(prediction.trendSecondsPerWeek, "under a week apart")
        XCTAssertEqual(prediction.seconds, (3 * 5400 + 2 * 5500) / 5.0, accuracy: 0.001)
    }

    func testGoalGapAndStandingAreReported() throws {
        let dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .menOpenSingle)
        let index = try XCTUnwrap(dataset.gridP.firstIndex(of: 40))
        let total = Double(dataset.overallS[index])

        let prediction = try XCTUnwrap(FinishPredictor.predict(
            from: [race(total: total, daysAgo: 7)], division: .menOpenSingle,
            dataset: dataset, goalSeconds: total - 120, now: now
        ))

        XCTAssertEqual(try XCTUnwrap(prediction.topPercent), 40, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(prediction.gapToGoalSeconds), 120, accuracy: 0.001)
    }

    /// 다른 디비전의 데이터로 순위를 매기지 않는다.
    func testStandingNeedsMatchingDataset() throws {
        let other = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .womenOpenSingle)
        let prediction = try XCTUnwrap(FinishPredictor.predict(
            from: [race(total: 5400, daysAgo: 7)], division: .menOpenSingle, dataset: other, now: now
        ))
        XCTAssertNil(prediction.topPercent)
    }

    /// 화면만 넘긴 기록(62초짜리 "완주")은 예측의 근거가 되지 않는다.
    func testImplausibleRacesAreIgnored() throws {
        func tapped(daysAgo: Double) -> CompletedWorkout {
            var segments: [SegmentRecord] = []
            let start = now.addingTimeInterval(-daysAgo * 86_400 - 62)
            var cursor = start
            for kind in StationKind.standardOrder {
                segments.append(SegmentRecord(
                    segmentId: UUID(), index: segments.count, type: .run,
                    startedAt: cursor, endedAt: cursor.addingTimeInterval(4), plannedDistanceMeters: 1000
                ))
                cursor = cursor.addingTimeInterval(4)
                segments.append(SegmentRecord(
                    segmentId: UUID(), index: segments.count, type: .station,
                    startedAt: cursor, endedAt: cursor.addingTimeInterval(3.75),
                    stationDisplayName: kind.displayName
                ))
                cursor = cursor.addingTimeInterval(3.75)
            }
            return CompletedWorkout(
                templateName: "HYROX", division: .menOpenSingle, startedAt: start, finishedAt: cursor, segments: segments
            )
        }
        XCTAssertTrue(tapped(daysAgo: 1).isStandardHyroxCourse)
        XCTAssertNil(FinishPredictor.predict(from: [tapped(daysAgo: 1)], division: .menOpenSingle, now: now))

        // 진짜 기록이 섞여 있으면 그것만 쓴다 — 더 최근의 가짜 기록이 끼어들지 않는다.
        let prediction = try XCTUnwrap(FinishPredictor.predict(
            from: [tapped(daysAgo: 1), race(total: 5400, daysAgo: 9), tapped(daysAgo: 2)],
            division: .menOpenSingle, now: now
        ))
        XCTAssertEqual(prediction.seconds, 5400, accuracy: 0.001)
        XCTAssertEqual(prediction.basedOn, 1)
    }
}
