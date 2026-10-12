//
//  CoachInsightTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class CoachInsightTests: XCTestCase {

    private var dataset: PaceDataset!

    override func setUpWithError() throws {
        dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .menOpenSingle)
    }

    private func race(runs: [Double], stations: [Double]) -> CompletedWorkout {
        var segments: [SegmentRecord] = []
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var cursor = start
        for (i, kind) in StationKind.standardOrder.enumerated() {
            segments.append(SegmentRecord(segmentId: UUID(), index: segments.count, type: .run, startedAt: cursor,
                                          endedAt: cursor.addingTimeInterval(runs[i]), plannedDistanceMeters: 1000))
            cursor = cursor.addingTimeInterval(runs[i])
            segments.append(SegmentRecord(segmentId: UUID(), index: segments.count, type: .station, startedAt: cursor,
                                          endedAt: cursor.addingTimeInterval(stations[i]), stationDisplayName: kind.displayName))
            cursor = cursor.addingTimeInterval(stations[i])
        }
        return CompletedWorkout(templateName: "HYROX", division: .menOpenSingle, startedAt: start, finishedAt: cursor, segments: segments)
    }

    private func typical(at percent: Double) -> (running: Double, stations: [Double]) {
        let i = dataset.gridP.firstIndex(of: percent)!
        return (Double(dataset.components.runRoxS[i]),
                StationKind.standardOrder.map { Double(dataset.components.seconds(for: $0)![i]) })
    }

    func testWeakWallBallsLeadToTheLadderDrill() throws {
        let base = typical(at: 30)
        var stations = base.stations
        stations[7] += 90   // wall balls
        stations[1] -= 40   // sled push
        let workout = race(runs: Array(repeating: base.running / 8, count: 8), stations: stations)
        let diagnosis = try XCTUnwrap(WeaknessDiagnoser.diagnose(workout, dataset: dataset))

        let insights = CoachInsightBuilder.build(workout: workout, diagnosis: diagnosis, prediction: nil)

        guard case .standing(let top) = insights[0] else { return XCTFail("standing first") }
        XCTAssertEqual(top, diagnosis.finishTopPercent)
        guard case .biggestLoss(let kind, let lost, let drill) = insights[1] else { return XCTFail("loss second") }
        XCTAssertEqual(kind, .station(.wallBalls))
        XCTAssertGreaterThan(lost, 60)
        XCTAssertEqual(drill, .wallBallLadder)
        guard case .strength(let strong, let gained) = insights[2] else { return XCTFail("strength third") }
        XCTAssertEqual(strong, .station(.sledPush))
        XCTAssertGreaterThan(gained, 0)
        // 러닝을 8등분한 기록이라 페이스는 말하지 않는다.
        XCTAssertFalse(insights.contains { if case .fade = $0 { return true }; if case .evenPacing = $0 { return true }; return false })
    }

    func testDrillMapping() {
        XCTAssertEqual(CoachInsightBuilder.drill(for: .running), .compromisedRun)
        XCTAssertEqual(CoachInsightBuilder.drill(for: .station(.wallBalls)), .wallBallLadder)
        XCTAssertEqual(CoachInsightBuilder.drill(for: .station(.sledPull)), .stationIntervals)
    }

    func testFadingRunsAreCalledOut() {
        let base = typical(at: 50)
        let runs: [Double] = [300, 305, 310, 318, 325, 332, 340, 348]   // 마지막이 16% 느림
        let insights = CoachInsightBuilder.build(
            workout: race(runs: runs, stations: base.stations), diagnosis: nil, prediction: nil
        )
        guard case .fade(let percent) = insights.first else { return XCTFail("expected fade") }
        XCTAssertEqual(percent, 16, accuracy: 0.01)
    }

    func testEvenRunsArePraised_andMiddlingFadeSaysNothing() {
        let base = typical(at: 50)
        let even = CoachInsightBuilder.build(
            workout: race(runs: [300, 302, 301, 303, 304, 302, 305, 306], stations: base.stations),
            diagnosis: nil, prediction: nil
        )
        XCTAssertEqual(even, [.evenPacing])

        let middling = CoachInsightBuilder.build(
            workout: race(runs: [300, 302, 304, 306, 308, 310, 312, 315], stations: base.stations),
            diagnosis: nil, prediction: nil
        )
        XCTAssertTrue(middling.isEmpty, "5% is neither a fade nor notably even")
    }

    func testTrendIsIncludedOnlyWhenMeaningful() {
        func prediction(_ trend: Double?) -> FinishPrediction {
            FinishPrediction(
                division: .menOpenSingle, seconds: 5300, fastestSeconds: 5200, slowestSeconds: 5400,
                confidence: .high, basedOn: 3, latestDate: Date(), trendSecondsPerWeek: trend,
                topPercent: nil, gapToGoalSeconds: nil
            )
        }
        let base = typical(at: 50)
        let workout = race(runs: Array(repeating: base.running / 8, count: 8), stations: base.stations)
        XCTAssertEqual(CoachInsightBuilder.build(workout: workout, diagnosis: nil, prediction: prediction(-30)),
                       [.trend(secondsPerWeek: -30)])
        XCTAssertTrue(CoachInsightBuilder.build(workout: workout, diagnosis: nil, prediction: prediction(2)).isEmpty)
        XCTAssertTrue(CoachInsightBuilder.build(workout: workout, diagnosis: nil, prediction: prediction(nil)).isEmpty)
    }
}
