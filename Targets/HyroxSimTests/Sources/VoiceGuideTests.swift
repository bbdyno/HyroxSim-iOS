//
//  VoiceGuideTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import HyroxCore
@testable import HyroxSim

@MainActor
final class VoiceGuideTests: XCTestCase {

    private func cue(
        _ type: SegmentType, station: StationKind? = nil, seconds: Int, pace: VoiceCue.Pace?,
        next: SegmentType?, nextStation: StationKind? = nil
    ) -> VoiceCue {
        VoiceCue(finishedType: type, finishedStation: station, finishedSeconds: seconds, pace: pace,
                 nextType: next, nextStation: nextStation)
    }

    func testStationCueSaysTimeGapAndNext() {
        let text = VoiceGuide.text(for: cue(.station, station: .skiErg, seconds: 252, pace: .ahead(seconds: 8), next: .run))
        XCTAssertTrue(text.contains("SkiErg"))
        XCTAssertTrue(text.contains(VoiceGuide.spoken(252)))
        XCTAssertTrue(text.contains(VoiceGuide.spoken(8)))
        XCTAssertFalse(text.contains("%@") || text.contains("%1$") || text.contains("voice."))
        XCTAssertEqual(text.components(separatedBy: " ").filter { $0.isEmpty }.count, 0)
    }

    /// 록스존이 끝날 때는 기록을 읽지 않고 다음 구간만 알린다.
    func testRoxZoneCueOnlyAnnouncesNext() {
        let text = VoiceGuide.text(for: cue(.roxZone, seconds: 31, pace: nil, next: .station, nextStation: .sledPush))
        XCTAssertTrue(text.contains("Sled Push"))
        XCTAssertFalse(text.contains(VoiceGuide.spoken(31)))
    }

    func testLastSegmentAnnouncesCompletion() {
        let behind = VoiceGuide.text(for: cue(.station, station: .wallBalls, seconds: 400, pace: .behind(seconds: 35), next: nil))
        XCTAssertTrue(behind.contains(VoiceGuide.spoken(35)))
        XCTAssertFalse(behind.isEmpty)
        let noGoal = VoiceGuide.text(for: cue(.station, station: .wallBalls, seconds: 400, pace: nil, next: nil))
        XCTAssertLessThan(noGoal.count, behind.count, "no goal → no gap sentence")
    }

    func testSpokenDurationUsesMinutesAndSeconds() {
        XCTAssertFalse(VoiceGuide.spoken(252).contains(":"))
        XCTAssertNotEqual(VoiceGuide.spoken(252), VoiceGuide.spoken(8))
    }

    /// 꺼져 있으면 말하지 않는다 (기본값은 꺼짐).
    func testDisabledByDefault() {
        UserDefaults.standard.removeObject(forKey: VoiceGuide.enabledKey)
        XCTAssertFalse(VoiceGuide.isEnabled)
    }
}
