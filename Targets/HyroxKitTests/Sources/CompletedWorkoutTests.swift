import XCTest
@testable import HyroxKit

@MainActor
final class CompletedWorkoutTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }
    private func t(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    private func makeEngine() -> WorkoutEngine {
        let template = WorkoutTemplate(name: "Test", segments: [
            .run(distanceMeters: 1000),
            .roxZone(),
            .station(.skiErg, target: .distance(meters: 1000))
        ])
        return WorkoutEngine(template: template)
    }

    func testMakeCompletedWorkoutFromFinished() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(60))
        try engine.advance(at: t(90))
        try engine.advance(at: t(300))

        XCTAssertTrue(engine.isFinished)

        let workout = try engine.makeCompletedWorkout()
        XCTAssertEqual(workout.templateName, "Test")
        XCTAssertEqual(workout.segments.count, 3)
        XCTAssertEqual(workout.totalDuration, 300, accuracy: 0.001)
        XCTAssertEqual(workout.runSegments.count, 1)
        XCTAssertEqual(workout.roxZoneSegments.count, 1)
        XCTAssertEqual(workout.stationSegments.count, 1)
    }

    func testMakeCompletedWorkoutThrowsIfNotFinished() throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        XCTAssertThrowsError(try engine.makeCompletedWorkout()) { error in
            if case EngineError.invalidTransition = error { } else {
                XCTFail("Expected invalidTransition")
            }
        }
    }

    func testCompletedWorkoutTotalActiveDuration() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(60))
        try engine.advance(at: t(90))
        try engine.advance(at: t(300))

        let workout = try engine.makeCompletedWorkout()
        XCTAssertEqual(workout.totalActiveDuration, 300, accuracy: 0.001)
    }

    func testCompletedWorkoutWithHeartRateData() throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        engine.ingest(heartRateSample: HeartRateSample(timestamp: t(10), bpm: 140))
        engine.ingest(heartRateSample: HeartRateSample(timestamp: t(20), bpm: 160))
        try engine.advance(at: t(60))

        engine.ingest(heartRateSample: HeartRateSample(timestamp: t(70), bpm: 170))
        try engine.advance(at: t(90))
        try engine.advance(at: t(300))

        let workout = try engine.makeCompletedWorkout()
        XCTAssertNotNil(workout.averageHeartRate)
        XCTAssertEqual(workout.averageHeartRate, 156) // (140+160+170)/3
        XCTAssertEqual(workout.maxHeartRate, 170)
    }

    func testCompletedWorkoutCodableRoundTrip() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(60))
        try engine.advance(at: t(90))
        try engine.advance(at: t(300))

        let workout = try engine.makeCompletedWorkout()

        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(CompletedWorkout.self, from: data)

        XCTAssertEqual(decoded.templateName, workout.templateName)
        XCTAssertEqual(decoded.segments.count, workout.segments.count)
        XCTAssertEqual(decoded.totalDuration, workout.totalDuration, accuracy: 0.001)
    }

    func testCompletedWorkoutNilHeartRateWhenNoData() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(60))
        try engine.advance(at: t(90))
        try engine.advance(at: t(300))

        let workout = try engine.makeCompletedWorkout()
        XCTAssertNil(workout.averageHeartRate)
        XCTAssertNil(workout.maxHeartRate)
    }
}
