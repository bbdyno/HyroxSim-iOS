//
//  SeasonReportTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class SeasonReportTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }

    /// 공식 코스 완주. 러닝 8 × 1km.
    private func simulation(on day: Date, total: Double) -> CompletedWorkout {
        var segments: [SegmentRecord] = []
        var cursor = day
        let station = 240.0, run = (total - station * 8) / 8
        for kind in StationKind.standardOrder {
            segments.append(SegmentRecord(segmentId: UUID(), index: segments.count, type: .run, startedAt: cursor,
                                          endedAt: cursor.addingTimeInterval(run), plannedDistanceMeters: 1000))
            cursor = cursor.addingTimeInterval(run)
            segments.append(SegmentRecord(segmentId: UUID(), index: segments.count, type: .station, startedAt: cursor,
                                          endedAt: cursor.addingTimeInterval(station), stationDisplayName: kind.displayName))
            cursor = cursor.addingTimeInterval(station)
        }
        return CompletedWorkout(templateName: "HYROX", division: .menOpenSingle, startedAt: day, finishedAt: cursor, segments: segments)
    }

    /// 짧은 훈련: 런 1km + 스테이션 1개, 15분.
    private func training(on day: Date) -> CompletedWorkout {
        let mid = day.addingTimeInterval(300), end = day.addingTimeInterval(900)
        return CompletedWorkout(templateName: "Drill", division: .menOpenSingle, startedAt: day, finishedAt: end, segments: [
            SegmentRecord(segmentId: UUID(), index: 0, type: .run, startedAt: day, endedAt: mid, plannedDistanceMeters: 1000),
            SegmentRecord(segmentId: UUID(), index: 1, type: .station, startedAt: mid, endedAt: end,
                          stationDisplayName: StationKind.wallBalls.displayName)
        ])
    }

    func testEmptyYear() {
        let report = SeasonReportBuilder.build(year: 2026, workouts: [], races: [], calendar: calendar)
        XCTAssertTrue(report.isEmpty)
        XCTAssertNil(report.best)
        XCTAssertNil(report.busiestMonth)
        XCTAssertEqual(report.longestWeekStreak, 0)
    }

    func testCountsAndTotalsForTheYearOnly() {
        let workouts = [
            training(on: date(2025, 12, 30)),                    // 지난해 — 빠진다
            training(on: date(2026, 3, 2)), training(on: date(2026, 3, 4)),
            simulation(on: date(2026, 3, 9), total: 5400),
            training(on: date(2026, 6, 1))
        ]
        let report = SeasonReportBuilder.build(year: 2026, workouts: workouts, races: [], calendar: calendar)

        XCTAssertEqual(report.sessionCount, 4)
        XCTAssertEqual(report.fullSimulationCount, 1)
        XCTAssertEqual(report.runningMeters, 3 * 1000 + 8000)
        XCTAssertEqual(report.stationCount, 3 + 8)
        XCTAssertEqual(report.activeSeconds, 3 * 900 + 5400, accuracy: 0.001)
        XCTAssertEqual(report.busiestMonth, 3)
        XCTAssertFalse(report.isEmpty)
    }

    /// 3/2·3/4 는 같은 주, 3/9 는 다음 주 → 2주 연속. 6월은 따로.
    func testWeekStreak() {
        let workouts = [
            training(on: date(2026, 3, 2)), training(on: date(2026, 3, 4)),
            training(on: date(2026, 3, 9)), training(on: date(2026, 6, 1))
        ]
        let report = SeasonReportBuilder.build(year: 2026, workouts: workouts, races: [], calendar: calendar)
        XCTAssertEqual(report.activeWeeks, 3)
        XCTAssertEqual(report.longestWeekStreak, 2)
    }

    func testBestIsTheFastestOfRacesAndSimulations_andImprovementIsFromTheFirst() throws {
        let workouts = [
            simulation(on: date(2026, 2, 1), total: 5700),
            simulation(on: date(2026, 5, 1), total: 5300)
        ]
        let races = [RaceResult(eventName: "HYROX Seoul", date: date(2026, 9, 12), division: .menOpenSingle, totalSeconds: 5100)]
        let report = SeasonReportBuilder.build(year: 2026, workouts: workouts, races: races, calendar: calendar)

        let best = try XCTUnwrap(report.best)
        XCTAssertEqual(best.name, "HYROX Seoul")
        XCTAssertTrue(best.isOfficial)
        XCTAssertEqual(best.seconds, 5100)
        XCTAssertEqual(report.raceCount, 1)
        XCTAssertEqual(try XCTUnwrap(report.improvementSeconds), 600, accuracy: 0.001)
    }

    func testNoImprovementWhenTheFirstFinishWasTheFastest() {
        let workouts = [simulation(on: date(2026, 2, 1), total: 5000), simulation(on: date(2026, 5, 1), total: 5300)]
        let report = SeasonReportBuilder.build(year: 2026, workouts: workouts, races: [], calendar: calendar)
        XCTAssertNil(report.improvementSeconds)
        XCTAssertEqual(report.best?.seconds, 5000)
    }

    func testYearsListIsNewestFirstAcrossBothSources() {
        let years = SeasonReportBuilder.years(
            workouts: [training(on: date(2024, 5, 1)), training(on: date(2026, 5, 1))],
            races: [RaceResult(eventName: "R", date: date(2025, 4, 1), division: .menOpenSingle, totalSeconds: 5000)],
            calendar: calendar
        )
        XCTAssertEqual(years, [2026, 2025, 2024])
    }
}
