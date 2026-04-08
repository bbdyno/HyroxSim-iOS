//
//  WorkoutEngineSensorAttachTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

@MainActor
final class WorkoutEngineSensorAttachTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }
    private func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func makeEngine() -> WorkoutEngine {
        let template = WorkoutTemplate(name: "Test", segments: [
            .run(),
            .station(.skiErg, target: .distance(meters: 1000))
        ])
        return WorkoutEngine(template: template)
    }

    // MARK: - Location Stream Attachment

    func testLocationStreamSamplesIngested() async throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        let mockStream = MockLocationStream()
        let task = engine.attachLocationStream(mockStream)

        // Yield samples manually
        mockStream.yield(LocationSample(timestamp: t(1), latitude: 37.0, longitude: 127.0, horizontalAccuracy: 5))
        mockStream.yield(LocationSample(timestamp: t(2), latitude: 37.001, longitude: 127.0, horizontalAccuracy: 5))
        mockStream.yield(LocationSample(timestamp: t(3), latitude: 37.002, longitude: 127.0, horizontalAccuracy: 5))

        // Give the async stream time to deliver
        try await Task.sleep(for: .milliseconds(50))

        try engine.advance(at: t(5))

        XCTAssertEqual(engine.records[0].measurements.locationSamples.count, 3)

        task.cancel()
        mockStream.finish()
    }

    func testLocationStreamIgnoredForStation() async throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5)) // → station segment

        let mockStream = MockLocationStream()
        let task = engine.attachLocationStream(mockStream)

        mockStream.yield(LocationSample(timestamp: t(6), latitude: 37.0, longitude: 127.0, horizontalAccuracy: 5))
        try await Task.sleep(for: .milliseconds(50))

        try engine.finish(at: t(10))

        // Station doesn't track location
        XCTAssertEqual(engine.records[1].measurements.locationSamples.count, 0)

        task.cancel()
        mockStream.finish()
    }

    // MARK: - Heart Rate Stream Attachment

    func testHeartRateStreamSamplesIngested() async throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        let mockStream = MockHeartRateStream()
        let task = engine.attachHeartRateStream(mockStream)

        mockStream.yield(HeartRateSample(timestamp: t(1), bpm: 140))
        mockStream.yield(HeartRateSample(timestamp: t(2), bpm: 155))
        try await Task.sleep(for: .milliseconds(50))

        try engine.advance(at: t(5))

        XCTAssertEqual(engine.records[0].measurements.heartRateSamples.count, 2)
        XCTAssertEqual(engine.records[0].averageHeartRate, 147) // (140+155)/2

        task.cancel()
        mockStream.finish()
    }

    func testCancelledTaskStopsIngestion() async throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        let mockStream = MockLocationStream()
        let task = engine.attachLocationStream(mockStream)

        mockStream.yield(LocationSample(timestamp: t(1), latitude: 37.0, longitude: 127.0, horizontalAccuracy: 5))
        try await Task.sleep(for: .milliseconds(50))

        task.cancel()
        try await Task.sleep(for: .milliseconds(20))

        // This should not be ingested after cancellation
        mockStream.yield(LocationSample(timestamp: t(2), latitude: 37.1, longitude: 127.0, horizontalAccuracy: 5))
        try await Task.sleep(for: .milliseconds(50))

        try engine.advance(at: t(5))

        // Only the first sample should be present
        XCTAssertEqual(engine.records[0].measurements.locationSamples.count, 1)

        mockStream.finish()
    }
}
