//
//  SegmentStripTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class SegmentStripTests: XCTestCase {

    private let segments = HyroxPresets.template(for: .menOpenSingle).segments

    private func record(_ index: Int, seconds: Double, goal: Double?) -> SegmentRecord {
        let start = Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 1000)
        return SegmentRecord(
            segmentId: segments[index].id, index: index, type: segments[index].type,
            startedAt: start, endedAt: start.addingTimeInterval(seconds), goalDurationSeconds: goal
        )
    }

    func testStandardCourseHasSixteenCells_allUpcomingAtStart() {
        let cells = SegmentStripBuilder.cells(segments: segments, records: [], currentIndex: 0)
        XCTAssertEqual(cells.count, 16)
        XCTAssertEqual(cells.first, .current)
        XCTAssertTrue(cells.dropFirst().allSatisfy { $0 == .upcoming })
    }

    /// 런과 록스존은 한 칸으로 묶인다. 록스존(2번째 구간)에 있어도 첫 칸이 현재다.
    func testRunAndRoxZoneShareACell() {
        XCTAssertEqual(segments[1].type, .roxZone)
        let cells = SegmentStripBuilder.cells(
            segments: segments, records: [record(0, seconds: 300, goal: 320)], currentIndex: 1
        )
        XCTAssertEqual(cells[0], .current)
    }

    func testFinishedCellsCompareTheWholeBlockWithItsGoal() {
        // 구간 0 런(목표 320) + 1 록스존(목표 30) → 한 칸. 2 스테이션(목표 260). 3 록스존 …
        XCTAssertEqual(segments[2].type, .station)
        let records = [
            record(0, seconds: 300, goal: 320), record(1, seconds: 45, goal: 30),   // 345 vs 350 → 앞섬
            record(2, seconds: 280, goal: 260)                                      // 뒤짐
        ]
        let cells = SegmentStripBuilder.cells(segments: segments, records: records, currentIndex: 3)
        XCTAssertEqual(cells[0], .ahead)
        XCTAssertEqual(cells[1], .behind)
        XCTAssertEqual(cells[2], .current)
        XCTAssertEqual(cells[3], .upcoming)
    }

    func testNoGoalIsNeutral_andFinishedWorkoutHasNoCurrentCell() {
        let records = segments.indices.map { record($0, seconds: 100, goal: nil) }
        let cells = SegmentStripBuilder.cells(segments: segments, records: records, currentIndex: nil)
        XCTAssertEqual(cells.count, 16)
        XCTAssertTrue(cells.allSatisfy { $0 == .neutral })
    }
}
