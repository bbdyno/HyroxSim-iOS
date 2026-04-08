//
//  LiveSyncPacketTests.swift
//  HyroxKitTests
//
//  Created by Codex on 4/8/26.
//

import XCTest
@testable import HyroxKit

final class LiveSyncPacketTests: XCTestCase {

    func testWorkoutStartedPacketRoundTrips() throws {
        let template = WorkoutTemplate(
            name: "Mirror",
            segments: [.run(distanceMeters: 1000), .station(.skiErg, target: .distance(meters: 1000))]
        )
        let data = try LiveSyncPacketCoder.encode(.workoutStarted(template: template, origin: .watch))
        let packet = try LiveSyncPacketCoder.decode(data)

        guard case .workoutStarted(let decodedTemplate, let origin) = packet else {
            return XCTFail("Expected workoutStarted packet")
        }

        XCTAssertEqual(decodedTemplate.name, "Mirror")
        XCTAssertEqual(decodedTemplate.segments.count, 2)
        XCTAssertEqual(origin, .watch)
    }

    func testLiveStatePacketRoundTrips() throws {
        let state = LiveWorkoutState(
            segmentLabel: "RUN 1 / 1",
            segmentSubLabel: nil,
            segmentElapsedText: "01:23",
            totalElapsedText: "0:12:34",
            paceText: "4'12\" /km",
            distanceText: "820 m",
            heartRateText: "168",
            heartRateZoneRaw: HeartRateZone.z4.rawValue,
            stationNameText: nil,
            stationTargetText: nil,
            accentKindRaw: "run",
            isPaused: false,
            isFinished: false,
            isLastSegment: false,
            gpsStrong: true,
            gpsActive: true,
            templateName: "Mirror",
            totalSegmentCount: 3,
            currentSegmentIndex: 0,
            origin: .watch
        )
        let data = try LiveSyncPacketCoder.encode(.liveState(state))
        let packet = try LiveSyncPacketCoder.decode(data)

        guard case .liveState(let decodedState) = packet else {
            return XCTFail("Expected liveState packet")
        }

        XCTAssertEqual(decodedState.segmentLabel, "RUN 1 / 1")
        XCTAssertEqual(decodedState.heartRateText, "168")
        XCTAssertEqual(decodedState.origin, .watch)
    }

    func testCommandPacketRoundTrips() throws {
        let data = try LiveSyncPacketCoder.encode(.command(.pause))
        let packet = try LiveSyncPacketCoder.decode(data)

        guard case .command(let command) = packet else {
            return XCTFail("Expected command packet")
        }

        XCTAssertEqual(command, .pause)
    }
}
