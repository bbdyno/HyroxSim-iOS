import XCTest
@testable import HyroxKit

@MainActor
final class LiveMeasurementsSnapshotTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }
    private func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testSnapshotReturnsIngestedSamples() throws {
        let template = WorkoutTemplate(name: "Test", segments: [.run()])
        let engine = WorkoutEngine(template: template)
        try engine.start(at: t0)

        engine.ingest(locationSample: LocationSample(timestamp: t(1), latitude: 37.0, longitude: 127.0, horizontalAccuracy: 5))
        engine.ingest(locationSample: LocationSample(timestamp: t(2), latitude: 37.001, longitude: 127.0, horizontalAccuracy: 5))
        engine.ingest(locationSample: LocationSample(timestamp: t(3), latitude: 37.002, longitude: 127.0, horizontalAccuracy: 5))

        let snapshot = engine.liveMeasurementsSnapshot
        XCTAssertEqual(snapshot.locationSamples.count, 3)
    }

    func testSnapshotEmptyAfterAdvance() throws {
        let template = WorkoutTemplate(name: "Test", segments: [.run(), .station(.skiErg)])
        let engine = WorkoutEngine(template: template)
        try engine.start(at: t0)

        engine.ingest(locationSample: LocationSample(timestamp: t(1), latitude: 37.0, longitude: 127.0, horizontalAccuracy: 5))
        try engine.advance(at: t(5))

        let snapshot = engine.liveMeasurementsSnapshot
        XCTAssertEqual(snapshot.locationSamples.count, 0)
    }
}
