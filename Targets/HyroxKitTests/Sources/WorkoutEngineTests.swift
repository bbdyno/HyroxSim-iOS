import XCTest
@testable import HyroxKit

@MainActor
final class WorkoutEngineTests: XCTestCase {

    // MARK: - Helpers

    /// Base date for deterministic testing
    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    /// Returns a date offset by `seconds` from t0
    private func t(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    /// Creates a simple 3-segment template for testing
    private func makeTemplate(segmentCount: Int = 3) -> WorkoutTemplate {
        let segments = (0..<segmentCount).map { i -> WorkoutSegment in
            switch i % 3 {
            case 0: return .run()
            case 1: return .roxZone()
            default: return .station(.skiErg, target: .distance(meters: 1000))
            }
        }
        return WorkoutTemplate(name: "Test", segments: segments)
    }

    private func makeEngine(segmentCount: Int = 3) -> WorkoutEngine {
        WorkoutEngine(template: makeTemplate(segmentCount: segmentCount))
    }

    // MARK: - Start

    func testStartFromIdle() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        XCTAssertEqual(engine.currentSegmentIndex, 0)
        if case .running(let idx, _, _) = engine.state {
            XCTAssertEqual(idx, 0)
        } else {
            XCTFail("Expected running state")
        }
    }

    func testStartWithEmptyTemplateThrows() {
        let engine = WorkoutEngine(template: WorkoutTemplate(name: "Empty", segments: []))
        XCTAssertThrowsError(try engine.start(at: t0)) { error in
            XCTAssertEqual(error as? EngineError, .emptyTemplate)
        }
    }

    func testStartWhileRunningThrows() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        XCTAssertThrowsError(try engine.start(at: t(1))) { error in
            if case EngineError.invalidTransition(let from, let action) = error {
                XCTAssertEqual(from, "running")
                XCTAssertEqual(action, "start")
            } else {
                XCTFail("Expected invalidTransition")
            }
        }
    }

    // MARK: - Advance

    func testAdvanceCreatesRecord() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5))

        XCTAssertEqual(engine.records.count, 1)
        XCTAssertEqual(engine.currentSegmentIndex, 1)

        let record = engine.records[0]
        XCTAssertEqual(record.index, 0)
        XCTAssertEqual(record.duration, 5, accuracy: 0.001)
    }

    func testAdvanceAtLastSegmentFinishes() throws {
        let engine = makeEngine(segmentCount: 2)
        try engine.start(at: t0)
        try engine.advance(at: t(5))   // completes segment 0 → segment 1
        try engine.advance(at: t(10))  // completes segment 1 → finished

        XCTAssertTrue(engine.isFinished)
        XCTAssertEqual(engine.records.count, 2)
    }

    func testAdvanceWhileFinishedThrows() throws {
        let engine = makeEngine(segmentCount: 1)
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        XCTAssertTrue(engine.isFinished)

        XCTAssertThrowsError(try engine.advance(at: t(10))) { error in
            if case EngineError.invalidTransition(let from, _) = error {
                XCTAssertEqual(from, "finished")
            } else {
                XCTFail("Expected invalidTransition")
            }
        }
    }

    func testAdvanceWhilePausedThrows() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.pause(at: t(3))

        XCTAssertThrowsError(try engine.advance(at: t(5))) { error in
            if case EngineError.invalidTransition(let from, _) = error {
                XCTAssertEqual(from, "paused")
            } else {
                XCTFail("Expected invalidTransition")
            }
        }
    }

    // MARK: - Undo

    func testUndoRevertsToLastRecord() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        try engine.advance(at: t(10))
        XCTAssertEqual(engine.records.count, 2)
        XCTAssertEqual(engine.currentSegmentIndex, 2)

        try engine.undo(at: t(12))
        XCTAssertEqual(engine.records.count, 1)
        XCTAssertEqual(engine.currentSegmentIndex, 1)
    }

    func testUndoFromFinishedReturnsToRunning() throws {
        let engine = makeEngine(segmentCount: 1)
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        XCTAssertTrue(engine.isFinished)

        try engine.undo(at: t(7))
        XCTAssertFalse(engine.isFinished)
        XCTAssertEqual(engine.currentSegmentIndex, 0)
        XCTAssertEqual(engine.records.count, 0)
    }

    func testUndoWithNoRecordsThrows() throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        XCTAssertThrowsError(try engine.undo(at: t(1))) { error in
            XCTAssertEqual(error as? EngineError, .nothingToUndo)
        }
    }

    func testUndoFromIdleThrows() {
        let engine = makeEngine()
        XCTAssertThrowsError(try engine.undo(at: t0)) { error in
            if case EngineError.invalidTransition = error { } else {
                XCTFail("Expected invalidTransition")
            }
        }
    }

    // MARK: - Pause / Resume

    func testPauseFromRunning() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.pause(at: t(5))

        if case .paused(let idx, let segElapsed, let totElapsed) = engine.state {
            XCTAssertEqual(idx, 0)
            XCTAssertEqual(segElapsed, 5, accuracy: 0.001)
            XCTAssertEqual(totElapsed, 5, accuracy: 0.001)
        } else {
            XCTFail("Expected paused state")
        }
    }

    func testSegmentElapsedFreezesDuringPause() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.pause(at: t(5))

        // Even though "time passes", elapsed stays frozen
        XCTAssertEqual(engine.segmentElapsed(at: t(100)), 5, accuracy: 0.001)
        XCTAssertEqual(engine.totalElapsed(at: t(100)), 5, accuracy: 0.001)
    }

    func testResumeExcludesPausedTime() throws {
        let engine = makeEngine()
        try engine.start(at: t0)       // t=0
        try engine.pause(at: t(5))     // t=5, segElapsed=5, totalElapsed=5
        try engine.resume(at: t(15))   // t=15, 10s paused

        // After resume, totalElapsed should be 5 (active time before pause)
        // Plus any additional running time from t=15 onward
        XCTAssertEqual(engine.totalElapsed(at: t(15)), 5, accuracy: 0.001)
        XCTAssertEqual(engine.totalElapsed(at: t(20)), 10, accuracy: 0.001) // 5 + 5 new

        XCTAssertEqual(engine.segmentElapsed(at: t(15)), 5, accuracy: 0.001)
        XCTAssertEqual(engine.segmentElapsed(at: t(20)), 10, accuracy: 0.001)
    }

    func testPauseFromNonRunningThrows() throws {
        let engine = makeEngine()
        XCTAssertThrowsError(try engine.pause(at: t0)) // idle

        try engine.start(at: t0)
        try engine.pause(at: t(1))
        XCTAssertThrowsError(try engine.pause(at: t(2))) // already paused
    }

    func testResumeFromNonPausedThrows() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        XCTAssertThrowsError(try engine.resume(at: t(1))) // running, not paused
    }

    // MARK: - Finish

    func testFinishFromRunning() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.finish(at: t(10))

        XCTAssertTrue(engine.isFinished)
        XCTAssertEqual(engine.records.count, 1) // current segment recorded
        XCTAssertEqual(engine.records[0].index, 0)
    }

    func testFinishFromPaused() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.pause(at: t(5))
        try engine.finish(at: t(15))

        XCTAssertTrue(engine.isFinished)
        XCTAssertEqual(engine.records.count, 1)
    }

    func testFinishFromIdleThrows() {
        let engine = makeEngine()
        XCTAssertThrowsError(try engine.finish(at: t0)) { error in
            if case EngineError.invalidTransition(let from, _) = error {
                XCTAssertEqual(from, "idle")
            } else {
                XCTFail("Expected invalidTransition")
            }
        }
    }

    func testFinishFromFinishedThrows() throws {
        let engine = makeEngine(segmentCount: 1)
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        XCTAssertTrue(engine.isFinished)

        XCTAssertThrowsError(try engine.finish(at: t(10))) { error in
            if case EngineError.invalidTransition(let from, _) = error {
                XCTAssertEqual(from, "finished")
            } else {
                XCTFail("Expected invalidTransition")
            }
        }
    }

    // MARK: - Time Calculations

    func testSegmentElapsedDuringRunning() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        XCTAssertEqual(engine.segmentElapsed(at: t(5)), 5, accuracy: 0.001)
    }

    func testSegmentElapsedResetsOnAdvance() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        // After advance, segment just started at t=5
        XCTAssertEqual(engine.segmentElapsed(at: t(5)), 0, accuracy: 0.001)
        XCTAssertEqual(engine.segmentElapsed(at: t(8)), 3, accuracy: 0.001)
    }

    func testTotalElapsedAccumulates() throws {
        let engine = makeEngine()
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        XCTAssertEqual(engine.totalElapsed(at: t(8)), 8, accuracy: 0.001)
    }

    func testTotalElapsedWhenIdle() {
        let engine = makeEngine()
        XCTAssertEqual(engine.totalElapsed(at: t0), 0)
    }

    func testTotalElapsedWhenFinished() throws {
        let engine = makeEngine(segmentCount: 1)
        try engine.start(at: t0)
        try engine.advance(at: t(10))
        // Finished: totalElapsed = finishedAt - workoutStartedAt = 10
        XCTAssertEqual(engine.totalElapsed(at: t(999)), 10, accuracy: 0.001)
    }

    // MARK: - Queries

    func testCurrentSegmentAndNext() throws {
        let engine = makeEngine()
        try engine.start(at: t0)

        XCTAssertEqual(engine.currentSegment?.type, .run)
        XCTAssertEqual(engine.nextSegment?.type, .roxZone)
        XCTAssertFalse(engine.isLastSegment)
    }

    func testIsLastSegment() throws {
        let engine = makeEngine(segmentCount: 2)
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        XCTAssertTrue(engine.isLastSegment)
        XCTAssertNil(engine.nextSegment)
    }

    func testCurrentSegmentNilWhenIdle() {
        let engine = makeEngine()
        XCTAssertNil(engine.currentSegment)
        XCTAssertNil(engine.currentSegmentIndex)
    }

    func testCurrentSegmentNilWhenFinished() throws {
        let engine = makeEngine(segmentCount: 1)
        try engine.start(at: t0)
        try engine.advance(at: t(5))
        XCTAssertNil(engine.currentSegment)
    }

    // MARK: - Full Scenario

    func testFullHyroxPresetCompletion() throws {
        let template = HyroxPresets.template(for: .menOpenSingle)
        let engine = WorkoutEngine(template: template)
        try engine.start(at: t0)

        for i in 0..<31 {
            let time = t(Double((i + 1) * 60)) // 1 min per segment
            try engine.advance(at: time)
        }

        XCTAssertTrue(engine.isFinished)
        XCTAssertEqual(engine.records.count, 31)
        XCTAssertEqual(engine.totalElapsed(at: t(9999)), 31 * 60, accuracy: 0.001)

        // Last record should be a Wall Balls station
        XCTAssertEqual(engine.records.last?.type, .station)
    }
}
