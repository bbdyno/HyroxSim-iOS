//
//  TrainingPlanTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class TrainingPlanTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 2   // 월요일 시작
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 9))!
    }

    func testPhaseBoundaries() {
        XCTAssertEqual(TrainingPhase.phase(weeksToRace: 0), .raceWeek)
        XCTAssertEqual(TrainingPhase.phase(weeksToRace: 1), .taper)
        XCTAssertEqual(TrainingPhase.phase(weeksToRace: 2), .peak)
        XCTAssertEqual(TrainingPhase.phase(weeksToRace: 3), .peak)
        XCTAssertEqual(TrainingPhase.phase(weeksToRace: 4), .build)
        XCTAssertEqual(TrainingPhase.phase(weeksToRace: 8), .build)
        XCTAssertEqual(TrainingPhase.phase(weeksToRace: 9), .base)
    }

    func testPastRaceHasNoPlan() {
        XCTAssertNil(TrainingPlanBuilder.build(
            raceDate: date(2026, 10, 1), today: date(2026, 10, 12), calendar: calendar
        ))
    }

    /// 2026-10-12(월) → 2026-11-07(토). 대회 주까지 3주 차이 → 4개 주.
    func testWeeksCountDownToRaceWeek() throws {
        let plan = try XCTUnwrap(TrainingPlanBuilder.build(
            raceDate: date(2026, 11, 7), today: date(2026, 10, 12), calendar: calendar
        ))
        XCTAssertEqual(plan.weeks.map(\.weeksToRace), [3, 2, 1, 0])
        XCTAssertEqual(plan.weeks.map(\.phase), [.peak, .peak, .taper, .raceWeek])
        XCTAssertFalse(plan.isTruncated)
        XCTAssertEqual(plan.currentWeek?.startDate, calendar.startOfDay(for: date(2026, 10, 12)))
        XCTAssertEqual(plan.weeks[1].startDate, calendar.startOfDay(for: date(2026, 10, 19)))
    }

    func testRaceThisWeekIsJustRaceWeek() throws {
        let plan = try XCTUnwrap(TrainingPlanBuilder.build(
            raceDate: date(2026, 10, 17), today: date(2026, 10, 12), calendar: calendar
        ))
        XCTAssertEqual(plan.weeks.count, 1)
        XCTAssertEqual(plan.weeks[0].phase, .raceWeek)
        XCTAssertEqual(plan.weeks[0].items.last, .race)
    }

    /// 풀 시뮬레이션은 대회 2~3주 전에만. 대회 직전 주와 대회 주에는 없다.
    func testFullSimulationOnlyInPeakWeeks() throws {
        let plan = try XCTUnwrap(TrainingPlanBuilder.build(
            raceDate: date(2027, 1, 16), today: date(2026, 10, 12), calendar: calendar
        ))
        for week in plan.weeks {
            let hasFull = week.items.contains(.fullSimulation)
            XCTAssertEqual(hasFull, week.phase == .peak, "week \(week.weeksToRace)")
        }
        XCTAssertEqual(plan.weeks.filter { $0.items.contains(.race) }.count, 1)
        XCTAssertEqual(plan.weeks.last?.items.last, .race)
        // 대회에 가까울수록 양이 줄어든다.
        XCTAssertEqual(plan.weeks.first { $0.phase == .build }?.items.count, 3)
        XCTAssertEqual(plan.weeks.first { $0.phase == .taper }?.items.count, 2)
    }

    func testBaseWeeksIncludeAFitnessTestEveryFourWeeks() throws {
        let plan = try XCTUnwrap(TrainingPlanBuilder.build(
            raceDate: date(2027, 1, 30), today: date(2026, 10, 12), calendar: calendar
        ))
        let base = plan.weeks.filter { $0.phase == .base }
        XCTAssertFalse(base.isEmpty)
        for week in base {
            XCTAssertEqual(
                week.items.contains(.session(.pftBenchmark)), week.weeksToRace % 4 == 0, "week \(week.weeksToRace)"
            )
        }
    }

    func testWallBallWeaknessPutsTheLadderInEveryBuildWeek() throws {
        let race = date(2026, 12, 12), today = date(2026, 10, 12)
        let plain = try XCTUnwrap(TrainingPlanBuilder.build(raceDate: race, today: today, calendar: calendar))
        let focused = try XCTUnwrap(TrainingPlanBuilder.build(
            raceDate: race, today: today,
            weaknesses: [.station(.sledPush), .station(.wallBalls)], calendar: calendar
        ))
        let buildWeeks = focused.weeks.filter { $0.phase == .build }
        XCTAssertFalse(buildWeeks.isEmpty)
        XCTAssertTrue(buildWeeks.allSatisfy { $0.items.contains(.session(.wallBallLadder)) })
        XCTAssertFalse(plain.weeks.filter { $0.phase == .build }.allSatisfy { $0.items.contains(.session(.wallBallLadder)) })
    }

    func testRunningWeaknessAddsCompromisedRunsInBase() throws {
        let plan = try XCTUnwrap(TrainingPlanBuilder.build(
            raceDate: date(2027, 2, 13), today: date(2026, 10, 12), weaknesses: [.running], calendar: calendar
        ))
        let week = try XCTUnwrap(plan.weeks.first { $0.phase == .base && $0.weeksToRace % 4 != 0 })
        XCTAssertEqual(week.items.filter { $0 == .session(.compromisedRun) }.count, 2)
    }

    func testFarRaceIsTruncated() throws {
        let plan = try XCTUnwrap(TrainingPlanBuilder.build(
            raceDate: date(2027, 9, 1), today: date(2026, 10, 12), calendar: calendar
        ))
        XCTAssertEqual(plan.weeks.count, TrainingPlanBuilder.maxWeeks)
        XCTAssertTrue(plan.isTruncated)
        XCTAssertFalse(plan.weeks.contains { $0.items.contains(.race) })
    }
}
