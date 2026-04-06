//
//  WorkoutBuilderViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxKit
@testable import HyroxSim

@MainActor
final class WorkoutBuilderViewModelTests: XCTestCase {

    private func makePersistence() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    // MARK: - Empty Init

    func testEmptyInit() throws {
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: try makePersistence())
        XCTAssertTrue(vm.isEmpty)
        XCTAssertFalse(vm.canSave)
        XCTAssertFalse(vm.canStart)
        XCTAssertEqual(vm.segments.count, 0)
    }

    // MARK: - Preset Init

    func testPresetInit() throws {
        let preset = HyroxPresets.menOpenSingle
        let vm = WorkoutBuilderViewModel(startingFrom: preset, persistence: try makePersistence())
        XCTAssertEqual(vm.segments.count, 31)
        XCTAssertEqual(vm.division, .menOpenSingle)

        // Segments should have new UUIDs (cloned)
        for (i, seg) in vm.segments.enumerated() {
            XCTAssertNotEqual(seg.id, preset.segments[i].id, "Segment \(i) should be cloned with new UUID")
        }
    }

    // MARK: - Add / Remove / Move

    func testAddSegment() throws {
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: try makePersistence())
        vm.addSegment(.run())
        XCTAssertEqual(vm.segments.count, 1)
        XCTAssertTrue(vm.canStart)
    }

    func testRemoveSegment() throws {
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: try makePersistence())
        vm.addSegment(.run())
        vm.removeSegment(at: 0)
        XCTAssertEqual(vm.segments.count, 0)
    }

    func testMoveSegment() throws {
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: try makePersistence())
        let seg0 = WorkoutSegment.run(distanceMeters: 500)
        let seg1 = WorkoutSegment.roxZone()
        let seg2 = WorkoutSegment.station(.skiErg)
        vm.addSegment(seg0)
        vm.addSegment(seg1)
        vm.addSegment(seg2)

        vm.moveSegment(from: 0, to: 2)
        XCTAssertEqual(vm.segments[0].type, .roxZone)
        XCTAssertEqual(vm.segments[1].type, .station)
        XCTAssertEqual(vm.segments[2].type, .run)
    }

    // MARK: - Estimated Duration

    func testEstimatedDurationPositive() throws {
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: try makePersistence())
        vm.addSegment(.run())
        vm.addSegment(.station(.skiErg))
        XCTAssertGreaterThan(vm.estimatedDurationSeconds, 0)
    }

    // MARK: - canSave / canStart

    func testCanSaveRequiresName() throws {
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: try makePersistence())
        vm.addSegment(.run())
        XCTAssertTrue(vm.canSave)

        vm.rename(to: "   ")
        XCTAssertFalse(vm.canSave)
        XCTAssertTrue(vm.canStart) // canStart doesn't require name
    }

    // MARK: - Save & Persist

    func testSaveAsTemplate() throws {
        let persistence = try makePersistence()
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: persistence)
        vm.addSegment(.run())
        vm.addSegment(.station(.wallBalls, target: .reps(count: 50)))

        let template = try vm.saveAsTemplate()
        XCTAssertEqual(template.segments.count, 2)

        let fetched = try persistence.fetchAllTemplates()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, template.id)
    }

    func testMakeTemplateForStartDoesNotPersist() throws {
        let persistence = try makePersistence()
        let vm = WorkoutBuilderViewModel(startingFrom: nil, persistence: persistence)
        vm.addSegment(.run())

        let template = try vm.makeTemplateForStart()
        XCTAssertEqual(template.segments.count, 1)

        let fetched = try persistence.fetchAllTemplates()
        XCTAssertEqual(fetched.count, 0) // Not persisted
    }
}
