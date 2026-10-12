//
//  LevelAssessmentTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class LevelAssessmentTests: XCTestCase {

    private var dataset: PaceDataset!

    override func setUpWithError() throws {
        dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .menOpenSingle)
    }

    private func index(ofTopPercent percent: Double) throws -> Int {
        try XCTUnwrap(dataset.gridP.firstIndex(of: percent))
    }

    /// 공식 코스 기록. `stationSeconds` 는 공식 순서, `runningSeconds` 는 러닝 8회에 고르게 나눈다.
    private func makeRace(runningSeconds: Double, stationSeconds: [Double], withRoxZone: Bool = false) -> CompletedWorkout {
        var segments: [SegmentRecord] = []
        var cursor = Date(timeIntervalSince1970: 1_800_000_000)
        let start = cursor
        func add(_ type: SegmentType, _ duration: Double, name: String? = nil, distance: Double? = nil) {
            segments.append(SegmentRecord(
                segmentId: UUID(), index: segments.count, type: type,
                startedAt: cursor, endedAt: cursor.addingTimeInterval(duration),
                stationDisplayName: name, plannedDistanceMeters: distance
            ))
            cursor = cursor.addingTimeInterval(duration)
        }
        let roxEach: Double = withRoxZone ? 30 : 0
        let roxCount: Double = withRoxZone ? 15 : 0
        let runEach = (runningSeconds - roxEach * roxCount) / 8
        for (i, kind) in StationKind.standardOrder.enumerated() {
            add(.run, runEach, distance: 1000)
            if withRoxZone { add(.roxZone, roxEach) }
            add(.station, stationSeconds[i], name: kind.displayName)
            if withRoxZone, i < 7 { add(.roxZone, roxEach) }
        }
        return CompletedWorkout(
            templateName: "HYROX", division: .menOpenSingle,
            startedAt: start, finishedAt: cursor, segments: segments
        )
    }

    private func typicalStations(at index: Int) -> [Double] {
        StationKind.standardOrder.map { Double(dataset.components.seconds(for: $0)![index]) }
    }

    // MARK: - 수준 판정

    func testFinishTimeOnTheGridMapsToThatPercentile() throws {
        let i = try index(ofTopPercent: 30)
        let result = try XCTUnwrap(LevelAssessor.assess(finishSeconds: Double(dataset.overallS[i]), dataset: dataset))

        XCTAssertEqual(result.overallTopPercent, 30, accuracy: 0.001)
        XCTAssertFalse(result.isOverallClamped)
        XCTAssertEqual(result.division, .menOpenSingle)
        XCTAssertEqual(result.athletes, dataset.coverage.athletesWithFinishTime)
        XCTAssertNil(result.ageGroup)
    }

    func testBetweenGridPointsIsInterpolated() throws {
        let i = try index(ofTopPercent: 30)
        let midpoint = Double(dataset.overallS[i] + dataset.overallS[i + 1]) / 2
        let result = try XCTUnwrap(LevelAssessor.assess(finishSeconds: midpoint, dataset: dataset))
        let expected = (dataset.gridP[i] + dataset.gridP[i + 1]) / 2
        XCTAssertEqual(result.overallTopPercent, expected, accuracy: 0.01)
    }

    func testFasterIsAlwaysABetterStanding() throws {
        var previous = 0.0
        for seconds in stride(from: 3400.0, through: 12000.0, by: 137) {
            let percent = try XCTUnwrap(LevelAssessor.assess(finishSeconds: seconds, dataset: dataset)).overallTopPercent
            XCTAssertGreaterThanOrEqual(percent, previous, "\(seconds)s")
            previous = percent
        }
    }

    func testOutsideTheDataIsClampedAndSaysSo() throws {
        let faster = try XCTUnwrap(LevelAssessor.assess(finishSeconds: 3000, dataset: dataset))
        XCTAssertEqual(faster.overallTopPercent, dataset.gridP.first)
        XCTAssertTrue(faster.isOverallClamped)
        XCTAssertNil(faster.nextMilestone, "nothing left to chase")

        let slower = try XCTUnwrap(LevelAssessor.assess(finishSeconds: 20_000, dataset: dataset))
        XCTAssertEqual(slower.overallTopPercent, dataset.gridP.last)
        XCTAssertTrue(slower.isOverallClamped)
    }

    func testNextMilestoneIsTheNearestLineAhead() throws {
        // 상위 30% → 다음 선은 20%.
        let i30 = try index(ofTopPercent: 30)
        let i20 = try index(ofTopPercent: 20)
        let finish = Double(dataset.overallS[i30]) + 10   // 30% 를 살짝 넘긴 기록
        let milestone = try XCTUnwrap(
            LevelAssessor.assess(finishSeconds: finish, dataset: dataset)?.nextMilestone
        )
        XCTAssertEqual(milestone.topPercent, 30)
        XCTAssertEqual(milestone.gapSeconds, 10, accuracy: 0.001)

        // 정확히 30% 인 기록은 30% 선을 이미 넘은 것이므로 20% 를 본다.
        let exact = try XCTUnwrap(
            LevelAssessor.assess(finishSeconds: Double(dataset.overallS[i30]), dataset: dataset)?.nextMilestone
        )
        XCTAssertEqual(exact.topPercent, 20)
        XCTAssertEqual(exact.finishSeconds, Double(dataset.overallS[i20]))
        XCTAssertEqual(exact.gapSeconds, Double(dataset.overallS[i30] - dataset.overallS[i20]))
    }

    func testAgeGroupStandingUsesItsOwnCurve() throws {
        let group = try XCTUnwrap(dataset.ageGroups.first { $0.ageGroup == "40-44" } ?? dataset.ageGroups.first)
        let i = try XCTUnwrap(group.gridP.firstIndex(of: 50))
        let result = try XCTUnwrap(
            LevelAssessor.assess(finishSeconds: Double(group.overallS[i]), dataset: dataset, ageGroup: group.ageGroup)
        )
        let standing = try XCTUnwrap(result.ageGroup)
        XCTAssertEqual(standing.label, group.ageGroup)
        XCTAssertEqual(standing.topPercent, 50, accuracy: 0.001)
        XCTAssertEqual(standing.athletes, group.n)
        XCTAssertFalse(standing.isClamped)
    }

    func testUnknownAgeGroupFallsBackToOverallOnly() throws {
        let result = try XCTUnwrap(LevelAssessor.assess(finishSeconds: 5000, dataset: dataset, ageGroup: "nope"))
        XCTAssertNil(result.ageGroup)
    }

    func testAgeToGroupLookup() throws {
        let labels = LevelAssessor.ageGroups(in: dataset)
        XCTAssertFalse(labels.isEmpty)
        XCTAssertEqual(labels, labels.sorted { Int($0.prefix { $0.isNumber })! < Int($1.prefix { $0.isNumber })! })
        XCTAssertEqual(LevelAssessor.ageGroup(forAge: 20, in: dataset), "16-24")
        XCTAssertNil(LevelAssessor.ageGroup(forAge: 5, in: dataset))
    }

    func testEveryDivisionCanBeAssessed() throws {
        let snapshot = try PaceReferenceLoader.loadBundledPaceData()
        for division in HyroxDivision.allCases {
            let data = try snapshot.dataset(for: division)
            let median = Double(data.overallS[data.overallS.count / 2])
            let result = try XCTUnwrap(LevelAssessor.assess(finishSeconds: median, dataset: data), "\(division)")
            XCTAssertEqual(result.division, division)
            XCTAssertGreaterThan(result.overallTopPercent, 30)
            XCTAssertLessThan(result.overallTopPercent, 70)
        }
    }

    // MARK: - 약점 진단

    /// 모든 구간이 같은 수준이면 약점도 강점도 없다.
    func testEvenRaceHasNoWeakness() throws {
        let i = try index(ofTopPercent: 30)
        let race = makeRace(runningSeconds: Double(dataset.components.runRoxS[i]), stationSeconds: typicalStations(at: i))
        XCTAssertTrue(race.isStandardHyroxCourse)

        let diagnosis = try XCTUnwrap(WeaknessDiagnoser.diagnose(race, dataset: dataset))

        XCTAssertEqual(diagnosis.finishTopPercent, 30, accuracy: 0.01)
        XCTAssertEqual(diagnosis.items.count, 9)
        XCTAssertTrue(diagnosis.weaknesses.isEmpty)
        XCTAssertTrue(diagnosis.strengths.isEmpty)
        for item in diagnosis.items {
            XCTAssertEqual(item.lostSeconds, 0, accuracy: 0.5, "\(item.kind)")
            XCTAssertEqual(item.levelTopPercent, 30, accuracy: 1.0, "\(item.kind)")
        }
    }

    func testSlowStationIsNamedAsTheWeakness_andFastOneAsStrength() throws {
        let i = try index(ofTopPercent: 30)
        var stations = typicalStations(at: i)
        let wallBalls = StationKind.standardOrder.firstIndex(of: .wallBalls)!
        let sledPush = StationKind.standardOrder.firstIndex(of: .sledPush)!
        stations[wallBalls] += 90
        stations[sledPush] -= 40
        let race = makeRace(runningSeconds: Double(dataset.components.runRoxS[i]), stationSeconds: stations)

        let diagnosis = try XCTUnwrap(WeaknessDiagnoser.diagnose(race, dataset: dataset))

        let worst = try XCTUnwrap(diagnosis.weaknesses.first)
        XCTAssertEqual(worst.kind, .station(.wallBalls))
        XCTAssertGreaterThan(worst.lostSeconds, 60)
        XCTAssertGreaterThan(worst.levelTopPercent, diagnosis.finishTopPercent, "wall balls rank worse than the finish")

        let best = try XCTUnwrap(diagnosis.strengths.first)
        XCTAssertEqual(best.kind, .station(.sledPush))
        XCTAssertLessThan(best.levelTopPercent, diagnosis.finishTopPercent)

        XCTAssertEqual(diagnosis.items.first?.kind, .station(.wallBalls), "sorted by time lost")
        XCTAssertEqual(diagnosis.recoverableSeconds, diagnosis.weaknesses.reduce(0) { $0 + $1.lostSeconds })
    }

    /// 록스존을 따로 잰 기록도 러닝과 합쳐서 같은 기준으로 비교한다.
    func testRoxZoneTimeCountsAsRunning() throws {
        let i = try index(ofTopPercent: 50)
        let running = Double(dataset.components.runRoxS[i])
        let without = makeRace(runningSeconds: running, stationSeconds: typicalStations(at: i))
        let with = makeRace(runningSeconds: running, stationSeconds: typicalStations(at: i), withRoxZone: true)
        XCTAssertTrue(with.isStandardHyroxCourse)

        let a = try XCTUnwrap(WeaknessDiagnoser.diagnose(without, dataset: dataset))
        let b = try XCTUnwrap(WeaknessDiagnoser.diagnose(with, dataset: dataset))

        let runA = try XCTUnwrap(a.items.first { $0.kind == .running })
        let runB = try XCTUnwrap(b.items.first { $0.kind == .running })
        XCTAssertEqual(runA.actualSeconds, running, accuracy: 0.001)
        XCTAssertEqual(runB.actualSeconds, running, accuracy: 0.001)
        XCTAssertEqual(a.finishTopPercent, b.finishTopPercent, accuracy: 0.001)
    }

    func testNonStandardWorkoutIsNotDiagnosed() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let custom = CompletedWorkout(
            templateName: "Custom", division: .menOpenSingle, startedAt: start,
            finishedAt: start.addingTimeInterval(600),
            segments: [SegmentRecord(
                segmentId: UUID(), index: 0, type: .run, startedAt: start,
                endedAt: start.addingTimeInterval(600), plannedDistanceMeters: 2000
            )]
        )
        XCTAssertNil(WeaknessDiagnoser.diagnose(custom, dataset: dataset))
    }
}
