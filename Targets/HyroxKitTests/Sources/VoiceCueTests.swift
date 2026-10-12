//
//  VoiceCueTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class VoiceCueTests: XCTestCase {

    private func station(_ kind: StationKind, goal: TimeInterval?) -> WorkoutSegment {
        WorkoutSegment(type: .station, goalDurationSeconds: goal, stationKind: kind)
    }

    private func run(goal: TimeInterval?) -> WorkoutSegment {
        WorkoutSegment(type: .run, distanceMeters: 1000, goalDurationSeconds: goal)
    }

    func testAheadBehindAndOnGoal() {
        let next = run(goal: 300)
        XCTAssertEqual(VoiceCue.make(finished: station(.skiErg, goal: 260), finishedSeconds: 252.4, next: next).pace,
                       .ahead(seconds: 8))
        XCTAssertEqual(VoiceCue.make(finished: station(.skiErg, goal: 260), finishedSeconds: 281, next: next).pace,
                       .behind(seconds: 21))
        XCTAssertEqual(VoiceCue.make(finished: station(.skiErg, goal: 260), finishedSeconds: 261.6, next: next).pace,
                       .onGoal)
    }

    func testNoGoalMeansNoPace() {
        let cue = VoiceCue.make(finished: station(.rowing, goal: nil), finishedSeconds: 270, next: nil)
        XCTAssertNil(cue.pace)
        XCTAssertEqual(cue.finishedSeconds, 270)
        XCTAssertEqual(cue.finishedStation, .rowing)
        XCTAssertNil(cue.nextType, "workout finished")
    }

    /// 록스존은 전환 구간이라 목표 대비를 말하지 않는다.
    func testRoxZoneDoesNotReportPace() {
        let rox = WorkoutSegment(type: .roxZone, goalDurationSeconds: 30)
        let cue = VoiceCue.make(finished: rox, finishedSeconds: 55, next: station(.sledPush, goal: 200))
        XCTAssertNil(cue.pace)
        XCTAssertEqual(cue.nextType, .station)
        XCTAssertEqual(cue.nextStation, .sledPush)
    }

    func testNextRunIsDescribed() {
        let cue = VoiceCue.make(finished: station(.wallBalls, goal: 300), finishedSeconds: 300, next: run(goal: 310))
        XCTAssertEqual(cue.nextType, .run)
        XCTAssertNil(cue.nextStation)
    }
}
