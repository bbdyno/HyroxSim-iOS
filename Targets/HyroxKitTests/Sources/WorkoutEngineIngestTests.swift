import XCTest
@testable import HyroxKit

@MainActor
final class WorkoutEngineIngestTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }
    private func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// Template: run → roxZone → station (3 segments)
    private func makeEngine() -> WorkoutEngine {
        let template = WorkoutTemplate(name: "Test", segments: [
            .run(),
            .roxZone(),
            .station(.skiErg, target: .distance(meters: 1000))
        ])
        return WorkoutEngine(template: template)
    }

    private func makeSample(at seconds: TimeInterval) -> LocationSample {
        LocationSample(
            timestamp: t(seconds),
            latitude: 37.5665 + seconds * 0.00001,
            longitude: 126.9780,
            horizontalAccuracy: 5
        )
    }

    private func makeHRSample(at seconds: TimeInterval, bpm: Int) -> HeartRateSample {
        HeartRateSample(timestamp: t(seconds), bpm: bpm)
    }

    // MARK: - Location Ingestion

    func testGPSSamplesRecordedForRunSegment() throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        // Segment 0 is a run — GPS should be captured
        engine.ingest(locationSample: makeSample(at: 1))
        engine.ingest(locationSample: makeSample(at: 2))
        engine.ingest(locationSample: makeSample(at: 3))

        try engine.advance(at: t(5))

        XCTAssertEqual(engine.records[0].measurements.locationSamples.count, 3)
    }

    func testGPSSamplesIgnoredForStationSegment() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5))   // → roxZone
        try engine.advance(at: t(10))  // → station

        // Segment 2 is a station — GPS should be ignored
        engine.ingest(locationSample: makeSample(at: 11))
        engine.ingest(locationSample: makeSample(at: 12))

        try engine.finish(at: t(15))

        let stationRecord = engine.records[2]
        XCTAssertEqual(stationRecord.measurements.locationSamples.count, 0)
    }

    func testGPSSamplesRecordedForRoxZone() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5)) // → roxZone (index 1)

        engine.ingest(locationSample: makeSample(at: 6))

        try engine.advance(at: t(10)) // → station (index 2)

        XCTAssertEqual(engine.records[1].measurements.locationSamples.count, 1)
    }

    // MARK: - Heart Rate Ingestion

    func testHRSamplesRecordedForStation() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        try engine.advance(at: t(10)) // → station

        engine.ingest(heartRateSample: makeHRSample(at: 11, bpm: 155))
        engine.ingest(heartRateSample: makeHRSample(at: 12, bpm: 160))

        try engine.finish(at: t(15))

        XCTAssertEqual(engine.records[2].measurements.heartRateSamples.count, 2)
        XCTAssertEqual(engine.records[2].averageHeartRate, 157) // (155+160)/2
    }

    func testHRSamplesRecordedForRunSegment() throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        engine.ingest(heartRateSample: makeHRSample(at: 1, bpm: 140))
        try engine.advance(at: t(5))

        XCTAssertEqual(engine.records[0].measurements.heartRateSamples.count, 1)
    }

    // MARK: - Ignored States

    func testIngestIgnoredWhenIdle() {
        let engine = makeEngine()
        engine.ingest(locationSample: makeSample(at: 0))
        engine.ingest(heartRateSample: makeHRSample(at: 0, bpm: 100))
        // No crash, no effect — engine is idle
    }

    func testIngestIgnoredWhenPaused() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.pause(at: t(3))

        engine.ingest(locationSample: makeSample(at: 4))
        engine.ingest(heartRateSample: makeHRSample(at: 4, bpm: 100))

        try engine.resume(at: t(10))
        try engine.advance(at: t(15))

        // Samples during pause should not be recorded
        XCTAssertEqual(engine.records[0].measurements.locationSamples.count, 0)
        XCTAssertEqual(engine.records[0].measurements.heartRateSamples.count, 0)
    }

    // MARK: - Buffer Reset

    func testBufferClearedOnAdvance() throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        engine.ingest(locationSample: makeSample(at: 1))
        try engine.advance(at: t(5)) // → roxZone

        // New segment buffer should be empty
        engine.ingest(heartRateSample: makeHRSample(at: 6, bpm: 150))
        try engine.advance(at: t(10)) // → station

        // roxZone record should have 0 GPS (none ingested after advance) + 1 HR
        XCTAssertEqual(engine.records[1].measurements.locationSamples.count, 0)
        XCTAssertEqual(engine.records[1].measurements.heartRateSamples.count, 1)
    }
}
