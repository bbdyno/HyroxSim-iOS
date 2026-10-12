//
//  RaceResultTextParserTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

/// 실제 결과 화면 두 장을 Vision 으로 인식한 결과를 그대로 옮겨 둔 자료로 검증한다.
/// (선수 이름 줄은 뺐다.)
final class RaceResultTextParserTests: XCTestCase {

    private func line(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> RecognizedTextLine {
        RecognizedTextLine(text: text, x: x, y: y, w: w, h: h)
    }

    /// 구간 표: Split | Time | Place.
    private var splitTable: [RecognizedTextLine] { [
        line("Place", 0.849, 0.036, 0.118, 0.022),
        line("Split", 0.140, 0.036, 0.108, 0.025),
        line("Time", 0.613, 0.036, 0.108, 0.025),
        line("Running !", 0.145, 0.083, 0.194, 0.027),
        line("00:05:03", 0.608, 0.084, 0.188, 0.022),
        line("00:03:57", 0.607, 0.126, 0.183, 0.026),
        line("01", 0.043, 0.129, 0.048, 0.022),
        line("10", 0.844, 0.129, 0.054, 0.020),
        line("1000m SkiErg", 0.140, 0.129, 0.280, 0.025),
        line("Running 2", 0.145, 0.170, 0.205, 0.030),
        line("00:04:00", 0.607, 0.171, 0.188, 0.026),
        line("23", 0.844, 0.216, 0.065, 0.025),
        line("50m Sled Push", 0.145, 0.216, 0.306, 0.022),
        line("00:01:37", 0.608, 0.216, 0.172, 0.025),
        line("02", 0.032, 0.218, 0.065, 0.022),
        line("00:04:17", 0.607, 0.259, 0.174, 0.026),
        line("Running 3", 0.150, 0.260, 0.199, 0.024),
        line("00:02:35", 0.607, 0.304, 0.184, 0.027),
        line("8", 0.855, 0.305, 0.032, 0.020),
        line("50m Sled Pull", 0.145, 0.305, 0.280, 0.022),
        line("03", 0.032, 0.308, 0.065, 0.022),
        line("Running 4", 0.139, 0.349, 0.210, 0.030),
        line("00:04:05", 0.607, 0.350, 0.188, 0.026),
        line("80m Burpee Broad", 0.151, 0.395, 0.371, 0.022),
        line("7", 0.844, 0.395, 0.043, 0.025),
        line("00:02:33", 0.608, 0.395, 0.183, 0.022),
        line("04", 0.032, 0.398, 0.065, 0.022),
        line("Jump", 0.139, 0.428, 0.124, 0.024),
        line("Running 5", 0.139, 0.469, 0.211, 0.028),
        line("00:04:17", 0.607, 0.473, 0.172, 0.020),
        line("00:04:12", 0.608, 0.515, 0.172, 0.022),
        line("1000m Row", 0.145, 0.515, 0.231, 0.020),
        line("l6", 0.844, 0.518, 0.054, 0.020),
        line("05", 0.032, 0.518, 0.059, 0.022),
        line("Running 6", 0.144, 0.558, 0.206, 0.032),
        line("00:04:04", 0.607, 0.560, 0.188, 0.023),
        line("58", 0.849, 0.605, 0.059, 0.022),
        line("200m Farmers Carry", 0.145, 0.605, 0.414, 0.022),
        line("00:01:28", 0.608, 0.605, 0.172, 0.022),
        line("06", 0.032, 0.608, 0.065, 0.022),
        line("Running 7", 0.145, 0.649, 0.205, 0.027),
        line("00:03:54", 0.607, 0.649, 0.183, 0.023),
        line("00:02:41", 0.607, 0.695, 0.172, 0.025),
        line("100m Sandbag", 0.140, 0.695, 0.301, 0.025),
        line("07", 0.032, 0.697, 0.059, 0.020),
        line("Lunges", 0.150, 0.728, 0.146, 0.020),
        line("00:04:14", 0.607, 0.769, 0.173, 0.025),
        line("Running 8", 0.145, 0.770, 0.204, 0.025),
        line("Wall Balls", 0.145, 0.815, 0.199, 0.023),
        line("00:03:56", 0.613, 0.815, 0.183, 0.023),
        line("10", 0.844, 0.815, 0.054, 0.022),
        line("08", 0.032, 0.818, 0.065, 0.020),
        line("00:03:58", 0.607, 0.860, 0.188, 0.023),
        line("34", 0.849, 0.860, 0.059, 0.022),
        line("Roxzone Time", 0.151, 0.860, 0.274, 0.020),
        line("00:33:51", 0.613, 0.904, 0.172, 0.023),
        line("Run Total", 0.145, 0.904, 0.199, 0.020),
        line("83", 0.849, 0.905, 0.065, 0.022),
        line("Best Run Lap", 0.145, 0.948, 0.270, 0.028),
        line("00:03:54", 0.613, 0.949, 0.178, 0.023),
        line("83", 0.849, 0.950, 0.065, 0.022)
    ] }

    /// 공유 카드: 이름 아래 줄에 시간.
    private var shareCard: [RecognizedTextLine] { [
        line("HYROX", 0.073, 0.072, 0.264, 0.042),
        line("ATHLETE RESULTS_", 0.540, 0.100, 0.319, 0.032),
        line("2025 ANAHEIM", 0.012, 0.128, 0.374, 0.037),
        line("1000M SKI-ERG", 0.546, 0.196, 0.215, 0.023),
        line("00:04:07", 0.546, 0.223, 0.184, 0.033),
        line("50M SLED PUSH", 0.540, 0.279, 0.239, 0.023),
        line("00:03:07", 0.546, 0.305, 0.185, 0.029),
        line("50M SLED PULL", 0.546, 0.361, 0.221, 0.023),
        line("00:04:10", 0.540, 0.384, 0.184, 0.037),
        line("80M BURPEE BROAD JUMP", 0.540, 0.438, 0.387, 0.023),
        line("00:03:20", 0.540, 0.466, 0.196, 0.037),
        line("1000M ROW", 0.546, 0.521, 0.166, 0.027),
        line("00:04:31", 0.540, 0.548, 0.184, 0.037),
        line("200M FARMERS CARRY", 0.546, 0.603, 0.325, 0.023),
        line("00:01:45", 0.540, 0.629, 0.185, 0.034),
        line("100M SANDBAG LUNGES", 0.546, 0.685, 0.344, 0.023),
        line("00:03:28", 0.539, 0.709, 0.198, 0.042),
        line("WALL BALLS", 0.546, 0.767, 0.184, 0.023),
        line("00:06:07", 0.539, 0.793, 0.191, 0.035),
        line("TOTAL TIME", 0.540, 0.849, 0.178, 0.023),
        line("01:03:29", 0.540, 0.872, 0.178, 0.037),
        line("TOTAL RUN-TIME", 0.546, 0.932, 0.245, 0.023),
        line("00:29:13", 0.540, 0.958, 0.178, 0.033)
    ] }

    // MARK: - 시간 읽기

    func testTimeParsing() {
        XCTAssertEqual(RaceResultTextParser.seconds(from: "00:05:03"), 303)
        XCTAssertEqual(RaceResultTextParser.seconds(from: "01:03:29"), 3809)
        XCTAssertEqual(RaceResultTextParser.seconds(from: "5:03"), 303)
        XCTAssertEqual(RaceResultTextParser.seconds(from: "OO:O4:l2"), 252, "common OCR slips")
        XCTAssertEqual(RaceResultTextParser.seconds(from: "00: 04: 12"), 252)
        XCTAssertNil(RaceResultTextParser.seconds(from: "10"))
        XCTAssertNil(RaceResultTextParser.seconds(from: "Running 2"))
        XCTAssertNil(RaceResultTextParser.seconds(from: "00:75:00"))
        XCTAssertNil(RaceResultTextParser.seconds(from: "00:00:00"))
        XCTAssertNil(RaceResultTextParser.seconds(from: "1000m"))
    }

    // MARK: - 구간 표

    func testSplitTableReadsEveryStation() {
        let result = RaceResultTextParser.parse(splitTable)
        XCTAssertEqual(result.stationSeconds, [
            .skiErg: 237, .sledPush: 97, .sledPull: 155, .burpeeBroadJumps: 153,
            .rowing: 252, .farmersCarry: 88, .sandbagLunges: 161, .wallBalls: 236
        ])
        XCTAssertTrue(result.missingStations.isEmpty)
    }

    /// 1번 랩은 "Running !" 로 잘못 읽혔다. 비어 있는 한 칸에 넣는다.
    func testSplitTableReadsAllRunLaps_includingTheMisreadOne() {
        let result = RaceResultTextParser.parse(splitTable)
        XCTAssertEqual(result.runLapSeconds, [303, 240, 257, 245, 257, 244, 234, 254])
    }

    func testSplitTableTotals() {
        let result = RaceResultTextParser.parse(splitTable)
        XCTAssertEqual(result.roxzoneSeconds, 238)
        XCTAssertEqual(result.runTotalSeconds, 2031)
        XCTAssertNil(result.totalSeconds, "the table has no finish time row")
        // 러닝 합계 + 록스존 + 스테이션 = 2031 + 238 + 1379.
        XCTAssertEqual(result.resolvedTotalSeconds, 3648)
        XCTAssertNil(result.eventName)
    }

    /// "Best Run Lap" 의 시간을 러닝이나 합계로 가져가면 안 된다.
    func testBestRunLapIsIgnored() {
        let result = RaceResultTextParser.parse(splitTable)
        XCTAssertEqual(result.runTotalSeconds, 2031)
        XCTAssertEqual(result.runLapSeconds[6], 234)
    }

    // MARK: - 공유 카드

    func testShareCardReadsStationsFromTheLineBelow() {
        let result = RaceResultTextParser.parse(shareCard)
        XCTAssertEqual(result.stationSeconds, [
            .skiErg: 247, .sledPush: 187, .sledPull: 250, .burpeeBroadJumps: 200,
            .rowing: 271, .farmersCarry: 105, .sandbagLunges: 208, .wallBalls: 367
        ])
    }

    func testShareCardTotalsAndEvent() {
        let result = RaceResultTextParser.parse(shareCard)
        XCTAssertEqual(result.totalSeconds, 3809)
        XCTAssertEqual(result.runTotalSeconds, 1753, "TOTAL RUN-TIME is the run total, not the finish time")
        XCTAssertNil(result.roxzoneSeconds)
        XCTAssertEqual(result.runLapSeconds, Array(repeating: nil, count: 8))
        XCTAssertEqual(result.resolvedTotalSeconds, 3809)
        XCTAssertEqual(result.eventName, "HYROX 2025 ANAHEIM")
    }

    // MARK: - 견고함

    func testNothingRecognisedIsEmpty() {
        XCTAssertTrue(RaceResultTextParser.parse([]).isEmpty)
        XCTAssertTrue(RaceResultTextParser.parse([line("Hello", 0.1, 0.1, 0.2, 0.03)]).isEmpty)
    }

    /// 일부만 찍힌 사진. 읽은 것만 채우고 나머지는 비워 둔다.
    func testCroppedTableKeepsWhatItFound() {
        let top = splitTable.filter { $0.y < 0.30 }
        let result = RaceResultTextParser.parse(top)
        XCTAssertEqual(result.stationSeconds, [.skiErg: 237, .sledPush: 97])
        XCTAssertEqual(result.missingStations.count, 6)
        XCTAssertNil(result.resolvedTotalSeconds)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - 대회 기록으로

    func testParsedCardBecomesAComparableRace() throws {
        let parsed = RaceResultTextParser.parse(shareCard)
        var stations: [String: Int] = [:]
        for (kind, seconds) in parsed.stationSeconds { stations[kind.dataKey!] = seconds }
        let race = RaceResult(
            eventName: "HYROX 2025 ANAHEIM", date: Date(timeIntervalSince1970: 1_760_000_000),
            division: .menOpenSingle, totalSeconds: try XCTUnwrap(parsed.resolvedTotalSeconds),
            stationSeconds: stations, runTotalSeconds: parsed.runTotalSeconds, source: .scan
        )
        XCTAssertTrue(race.hasAllStations)
        // 록스존을 몰라도 완주 − 스테이션 = 러닝 + 록스존.
        XCTAssertEqual(race.runningAndRoxzoneSeconds, 3809 - 1835)

        let workout = try XCTUnwrap(race.asCompletedWorkout())
        XCTAssertTrue(workout.isStandardHyroxCourse)
        XCTAssertEqual(workout.totalActiveDuration, 3809, accuracy: 0.001)

        let dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .menOpenSingle)
        let diagnosis = try XCTUnwrap(WeaknessDiagnoser.diagnose(workout, dataset: dataset))
        XCTAssertEqual(diagnosis.items.count, 9)
        XCTAssertEqual(diagnosis.items.first?.kind, .station(.wallBalls), "6:07 wall balls is the big loss")
    }

    func testRaceWithLapsAndRoxzoneKeepsTheTotal() throws {
        let parsed = RaceResultTextParser.parse(splitTable)
        var stations: [String: Int] = [:]
        for (kind, seconds) in parsed.stationSeconds { stations[kind.dataKey!] = seconds }
        let race = RaceResult(
            eventName: "HYROX", date: Date(timeIntervalSince1970: 1_760_000_000), division: .menProSingle,
            totalSeconds: try XCTUnwrap(parsed.resolvedTotalSeconds), stationSeconds: stations,
            runTotalSeconds: parsed.runTotalSeconds, runLapSeconds: parsed.runLapSeconds.compactMap { $0 },
            roxzoneSeconds: parsed.roxzoneSeconds, source: .scan
        )
        XCTAssertEqual(race.runningAndRoxzoneSeconds, 2031 + 238)
        let workout = try XCTUnwrap(race.asCompletedWorkout())
        // 랩 합(2034)은 공식 러닝 합계(2031)와 3초 다르다 — 화면의 반올림 차이.
        XCTAssertEqual(workout.totalActiveDuration, 2034 + 238 + 1379, accuracy: 0.001)
    }

    func testRaceMissingAStationCannotBeCompared() {
        let race = RaceResult(
            eventName: "HYROX", date: Date(), division: .menOpenSingle, totalSeconds: 5000,
            stationSeconds: ["skiErg": 240]
        )
        XCTAssertFalse(race.hasAllStations)
        XCTAssertNil(race.runningAndRoxzoneSeconds)
        XCTAssertNil(race.asCompletedWorkout())
    }

    func testRaceResultRoundTripsThroughJSON() throws {
        let race = RaceResult(
            eventName: "HYROX Seoul", date: Date(timeIntervalSince1970: 1_760_000_000), division: .mixedDouble,
            totalSeconds: 4321, stationSeconds: ["skiErg": 240], runTotalSeconds: 2000,
            runLapSeconds: [250, 251], roxzoneSeconds: 200, source: .scan, note: "PB"
        )
        let data = try JSONEncoder().encode([race])
        XCTAssertEqual(try JSONDecoder().decode([RaceResult].self, from: data), [race])
    }
}
