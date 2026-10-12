//
//  CoachWriterTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import HyroxCore
@testable import HyroxSim

final class CoachWriterTests: XCTestCase {

    func testEveryInsightHasASentenceWithItsNumbers() {
        let lines = CoachWriter.lines(for: [
            .standing(topPercent: 27.4),
            .biggestLoss(.station(.wallBalls), lostSeconds: 98, drill: .wallBallLadder),
            .strength(.running, gainedSeconds: 41),
            .fade(percent: 15.6),
            .evenPacing,
            .trend(secondsPerWeek: -24)
        ])
        XCTAssertEqual(lines.count, 6)
        XCTAssertTrue(lines[0].contains("27%"))
        XCTAssertTrue(lines[1].contains("01:38"))
        XCTAssertTrue(lines[1].contains(StationKind.wallBalls.displayName))
        XCTAssertTrue(lines[2].contains("00:41"))
        XCTAssertTrue(lines[3].contains("16"))
        XCTAssertTrue(lines[5].contains("00:24"))
        XCTAssertFalse(lines.contains { $0.contains("%@") || $0.contains("%1$") || $0.contains("coach.") })
    }

    func testNumbersAreExtractedAndNormalised() {
        XCTAssertEqual(CoachWriter.numbers(in: "Top 27%, lost 01:38 over 8 runs"), ["27", "1", "38", "8"])
        XCTAssertEqual(CoachWriter.numbers(in: "no digits"), [])
    }

    /// 모델이 쓴 글에 사실에 없는 숫자가 있으면 쓰지 않는다.
    func testModelOutputWithInventedNumbersIsRejected() {
        let facts = ["This finish puts you in the top 27% of race finishers.", "Wall Balls: 01:38 slower."]
        XCTAssertNotNil(CoachWriter.accepted(
            "You finished in the top 27%. Wall balls cost you 1:38, so make them your focus this week.", facts: facts
        ))
        XCTAssertNil(CoachWriter.accepted(
            "You finished in the top 27%. Do 5 sets of 20 wall balls three times a week.", facts: facts
        ), "5, 20 are not in the facts")
        XCTAssertNil(CoachWriter.accepted("ok", facts: facts), "too short")
        XCTAssertNil(CoachWriter.accepted(String(repeating: "word ", count: 200), facts: facts), "too long")
    }

    func testNoFactsMeansNoRewrite() async {
        let result = await CoachWriter.rewrite(lines: [], languageName: "English")
        XCTAssertNil(result)
    }
}
