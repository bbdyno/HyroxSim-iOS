//
//  HyroxPresetsTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
@testable import HyroxCore

final class HyroxPresetsTests: XCTestCase {

    func testAllPresetsCount() {
        XCTAssertEqual(HyroxPresets.all.count, 9)
    }

    func testEachPresetHas31Segments() {
        for preset in HyroxPresets.all {
            XCTAssertEqual(preset.segments.count, 31, "\(preset.name) should have 31 segments")
        }
    }

    func testLastSegmentIsWallBallsStation() {
        for preset in HyroxPresets.all {
            let last = preset.segments.last
            XCTAssertEqual(last?.type, .station, "\(preset.name) last segment should be station")
            XCTAssertEqual(last?.stationKind, .wallBalls, "\(preset.name) last station should be Wall Balls")
        }
    }

    func testMenProSingleWallBallsWeight() {
        let template = HyroxPresets.template(for: .menProSingle)
        let wallBalls = template.segments.last
        XCTAssertEqual(wallBalls?.weightKg, 9)
    }

    func testWomenOpenSingleWallBallsReps() {
        for division in [HyroxDivision.womenOpenSingle, .womenOpenDouble] {
            let template = HyroxPresets.template(for: division)
            let wallBalls = template.segments.last
            XCTAssertEqual(wallBalls?.stationTarget, .reps(count: 100), "\(division) wall balls reps")
            XCTAssertEqual(wallBalls?.weightKg, 4, "\(division) wall balls weight")
        }
    }

    func testAllPresetsAreBuiltIn() {
        for preset in HyroxPresets.all {
            XCTAssertTrue(preset.isBuiltIn, "\(preset.name) should be built-in")
        }
    }

    func testAllPresetsHaveDivision() {
        for preset in HyroxPresets.all {
            XCTAssertNotNil(preset.division, "\(preset.name) should have a division")
        }
    }

    func testTemplateForDivisionReturnsCorrectDivision() {
        for division in HyroxDivision.allCases {
            let template = HyroxPresets.template(for: division)
            XCTAssertEqual(template.division, division)
        }
    }

    func testAllPresetsValidate() {
        for preset in HyroxPresets.all {
            XCTAssertNoThrow(try preset.validate(), "\(preset.name) should pass validation")
        }
    }
}

// MARK: - Goal overrides on built-in presets

@MainActor
final class TemplateGoalOverrideStoreTests: XCTestCase {

    /// Runs `body` against a store backed by a throwaway UserDefaults suite.
    private func withStore(_ body: (TemplateGoalOverrideStore, UserDefaults) throws -> Void) rethrows {
        let suiteName = "com.hyroxsim.tests.goalOverride.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("could not create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(TemplateGoalOverrideStore(defaults: defaults), defaults)
    }

    /// Key format the iOS and watch screens rely on — do not change it.
    private func storageKey(for division: HyroxDivision) -> String {
        "com.hyroxsim.templateGoalOverride.\(division.rawValue)"
    }

    private func goals(_ template: WorkoutTemplate) -> [TimeInterval?] {
        template.logicalSegments.map(\.goalDurationSeconds)
    }

    /// The override stores only goals, so a spec correction (Women Open wall balls
    /// 75 → 100) reaches users who already saved a pace-planner goal.
    func testResolvedTemplateUsesCurrentSpecAndKeepsSavedGoals() {
        withStore { store, _ in
            let preset = HyroxPresets.template(for: .womenOpenSingle)

            // A template saved by an older build: outdated wall balls target and
            // weight, plus the user's own goals.
            var outdated = preset
            outdated.segments = preset.segments.map { segment in
                var copy = segment
                if copy.stationKind == .wallBalls {
                    copy.stationTarget = .reps(count: 75)
                    copy.weightKg = 3
                }
                switch copy.type {
                case .run: copy.goalDurationSeconds = 305
                case .station: copy.goalDurationSeconds = 275
                case .roxZone: copy.goalDurationSeconds = 25
                }
                return copy
            }
            store.save(outdated)

            let resolved = store.resolvedTemplate(from: preset)

            // Weights / targets come from the current spec…
            let wallBalls = resolved.segments.last
            XCTAssertEqual(wallBalls?.stationKind, .wallBalls)
            XCTAssertEqual(wallBalls?.stationTarget, .reps(count: 100))
            XCTAssertEqual(wallBalls?.weightKg, 4)

            // …while the saved goals survive.
            XCTAssertEqual(resolved.segments.count, preset.segments.count)
            XCTAssertEqual(goals(resolved), goals(outdated))
            XCTAssertEqual(resolved.segments.first { $0.type == .run }?.goalDurationSeconds, 305)
            XCTAssertEqual(wallBalls?.goalDurationSeconds, 275)
            XCTAssertEqual(resolved.segments.first { $0.type == .roxZone }?.goalDurationSeconds, 25)
        }
    }

    /// Legacy blobs (the whole `WorkoutTemplate`) are still readable and are
    /// treated as a goal delta, so old installs also pick up the spec fix.
    func testLegacyFullTemplateBlobIsReadAsGoalDelta() throws {
        try withStore { store, defaults in
            let preset = HyroxPresets.template(for: .womenOpenSingle)

            var legacy = preset
            legacy.segments = preset.segments.map { segment in
                var copy = segment
                if copy.stationKind == .wallBalls { copy.stationTarget = .reps(count: 75) }
                if copy.type == .run { copy.goalDurationSeconds = 312 }
                return copy
            }
            defaults.set(try JSONEncoder().encode(legacy), forKey: storageKey(for: .womenOpenSingle))

            let resolved = store.resolvedTemplate(from: preset)

            XCTAssertEqual(resolved.segments.last?.stationTarget, .reps(count: 100))
            XCTAssertEqual(resolved.segments.first { $0.type == .run }?.goalDurationSeconds, 312)
        }
    }

    func testRoxZoneOffSurvivesRoundTripAndKeepsStoredRoxGoals() throws {
        try withStore { store, defaults in
            let preset = HyroxPresets.template(for: .menOpenSingle)

            var customised = preset
            customised.segments = preset.segments.map { segment in
                var copy = segment
                if copy.type == .roxZone { copy.goalDurationSeconds = 42 }
                return copy
            }
            store.save(customised)
            store.save(customised.settingUsesRoxZone(false))

            let resolved = store.resolvedTemplate(from: preset)
            XCTAssertFalse(resolved.usesRoxZone)
            XCTAssertFalse(resolved.segments.contains { $0.type == .roxZone })
            XCTAssertEqual(resolved.segments.count, preset.logicalSegments.count)

            // Saving with ROX OFF must not wipe the transition goals the user set
            // while it was ON — there are simply no ROX segments to read them from.
            let data = try XCTUnwrap(defaults.data(forKey: storageKey(for: .menOpenSingle)))
            let stored = try JSONDecoder().decode(TemplateGoalOverride.self, from: data)
            XCTAssertFalse(stored.usesRoxZone)
            XCTAssertEqual(stored.roxGoalSeconds.count, 15)
            XCTAssertTrue(stored.roxGoalSeconds.allSatisfy { $0 == 42 })
        }
    }

    func testOverrideWithDifferentSegmentCountIsDiscarded() {
        withStore { store, _ in
            let preset = HyroxPresets.template(for: .menOpenSingle)

            var shortened = preset
            shortened.segments = Array(preset.segments.prefix(7))
            store.save(shortened)

            let resolved = store.resolvedTemplate(from: preset)
            XCTAssertEqual(resolved.segments.count, preset.segments.count)
            XCTAssertEqual(goals(resolved), goals(preset))
        }
    }

    func testNonBuiltInTemplateIsReturnedUnchanged() {
        withStore { store, _ in
            let custom = WorkoutTemplate(name: "Custom", segments: [.run(), .station(.skiErg)])
            store.save(custom)
            XCTAssertEqual(store.resolvedTemplate(from: custom), custom)
        }
    }

    func testSavePostsUpdateNotification() {
        withStore { store, _ in
            let preset = HyroxPresets.template(for: .menProSingle)
            expectation(forNotification: .hyroxTemplateGoalOverrideUpdated, object: nil) { note in
                (note.userInfo?["division"] as? String) == HyroxDivision.menProSingle.rawValue
            }
            store.save(preset)
            waitForExpectations(timeout: 1)
        }
    }
}
