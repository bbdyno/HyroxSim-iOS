//
//  SyncBidirectionalTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/8/26.
//

import XCTest
@testable import HyroxCore

final class SyncBidirectionalTests: XCTestCase {

    // MARK: - WorkoutOrigin

    func testWorkoutOriginRawValues() {
        XCTAssertEqual(WorkoutOrigin.phone.rawValue, "phone")
        XCTAssertEqual(WorkoutOrigin.watch.rawValue, "watch")
    }

    func testWorkoutOriginCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for origin in [WorkoutOrigin.phone, .watch] {
            let data = try encoder.encode(origin)
            let decoded = try decoder.decode(WorkoutOrigin.self, from: data)
            XCTAssertEqual(decoded, origin)
        }
    }

    // MARK: - HeartRateRelay

    func testHeartRateRelayCodable() throws {
        let relay = HeartRateRelay(bpm: 145, timestamp: Date(timeIntervalSinceReferenceDate: 1000))
        let data = try JSONEncoder().encode(relay)
        let decoded = try JSONDecoder().decode(HeartRateRelay.self, from: data)
        XCTAssertEqual(decoded.bpm, 145)
        XCTAssertEqual(decoded.timestamp, relay.timestamp)
    }

    func testHeartRateRelayDefaultTimestamp() {
        let before = Date()
        let relay = HeartRateRelay(bpm: 120)
        let after = Date()
        XCTAssertGreaterThanOrEqual(relay.timestamp, before)
        XCTAssertLessThanOrEqual(relay.timestamp, after)
    }

    // MARK: - LiveWorkoutState with origin

    func testLiveWorkoutStateOriginDefaultsToWatch() {
        let state = LiveWorkoutState(
            segmentLabel: "RUN 1 / 8", segmentSubLabel: nil,
            segmentElapsedText: "01:30", totalElapsedText: "0:01:30",
            paceText: "5'00\" /km", distanceText: "300 m",
            heartRateText: "145", heartRateZoneRaw: 3,
            goalText: "05:30", goalDeltaText: "-4:00", isOverGoal: false,
            stationNameText: nil, stationTargetText: nil,
            accentKindRaw: "run", isPaused: false, isFinished: false, isLastSegment: false,
            gpsStrong: true, gpsActive: true,
            templateName: "Test", totalSegmentCount: 31, currentSegmentIndex: 0
        )
        XCTAssertEqual(state.origin, .watch)
    }

    func testLiveWorkoutStateOriginPhone() {
        let state = LiveWorkoutState(
            segmentLabel: "RUN 1 / 8", segmentSubLabel: nil,
            segmentElapsedText: "01:30", totalElapsedText: "0:01:30",
            paceText: "5'00\" /km", distanceText: "300 m",
            heartRateText: "145", heartRateZoneRaw: 3,
            goalText: "05:30", goalDeltaText: "-4:00", isOverGoal: false,
            stationNameText: nil, stationTargetText: nil,
            accentKindRaw: "run", isPaused: false, isFinished: false, isLastSegment: false,
            gpsStrong: true, gpsActive: true,
            templateName: "Test", totalSegmentCount: 31, currentSegmentIndex: 0,
            origin: .phone
        )
        XCTAssertEqual(state.origin, .phone)
    }

    func testLiveWorkoutStateCodableWithOrigin() throws {
        let state = LiveWorkoutState(
            segmentLabel: "STATION 1 / 8", segmentSubLabel: "SkiErg",
            segmentElapsedText: "02:00", totalElapsedText: "0:15:00",
            paceText: "—", distanceText: "—",
            heartRateText: "160", heartRateZoneRaw: 4,
            goalText: "04:00", goalDeltaText: "-2:00", isOverGoal: false,
            stationNameText: "SkiErg", stationTargetText: "1000 m",
            accentKindRaw: "station", isPaused: false, isFinished: false, isLastSegment: false,
            gpsStrong: false, gpsActive: false,
            templateName: "Men Open", totalSegmentCount: 31, currentSegmentIndex: 4,
            origin: .phone
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LiveWorkoutState.self, from: data)
        XCTAssertEqual(decoded.origin, .phone)
        XCTAssertEqual(decoded.segmentLabel, "STATION 1 / 8")
        XCTAssertEqual(decoded.templateName, "Men Open")
    }

    // MARK: - MockSyncCoordinator

    @MainActor
    func testMockSyncCoordinatorTracksMessages() {
        let mock = MockSyncCoordinator()
        let template = WorkoutTemplate(
            name: "Test", segments: [.run(distanceMeters: 1000)]
        )
        mock.sendWorkoutStarted(template: template, origin: .phone)
        mock.sendCommand(.advance)
        mock.sendCommand(.pause)
        mock.sendHeartRateRelay(HeartRateRelay(bpm: 150))
        mock.sendWorkoutFinished(origin: .phone)

        XCTAssertEqual(mock.sentWorkoutStarted.count, 1)
        XCTAssertEqual(mock.sentWorkoutStarted[0].origin, .phone)
        XCTAssertEqual(mock.sentCommands, [.advance, .pause])
        XCTAssertEqual(mock.sentHeartRateRelays.count, 1)
        XCTAssertEqual(mock.sentHeartRateRelays[0].bpm, 150)
        XCTAssertEqual(mock.sentWorkoutFinished, [.phone])
    }

    // MARK: - WorkoutCommand

    func testWorkoutCommandRawValues() {
        XCTAssertEqual(WorkoutCommand.advance.rawValue, "advance")
        XCTAssertEqual(WorkoutCommand.pause.rawValue, "pause")
        XCTAssertEqual(WorkoutCommand.resume.rawValue, "resume")
        XCTAssertEqual(WorkoutCommand.end.rawValue, "end")
    }
}
