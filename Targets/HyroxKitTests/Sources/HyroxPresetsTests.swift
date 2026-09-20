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

// MARK: - 훈련 세션 라이브러리

final class HyroxTrainingSessionTests: XCTestCase {

    private func sessions(_ division: HyroxDivision = .menOpenSingle) -> [WorkoutTemplate] {
        HyroxPresets.trainingSessions(for: division)
    }

    private func session(
        _ kind: TrainingSessionKind,
        _ division: HyroxDivision = .menOpenSingle
    ) -> WorkoutTemplate {
        HyroxPresets.trainingSession(kind, for: division)
    }

    private func stations(_ template: WorkoutTemplate) -> [WorkoutSegment] {
        template.segments.filter { $0.type == .station }
    }

    private func runs(_ template: WorkoutTemplate) -> [WorkoutSegment] {
        template.segments.filter { $0.type == .run }
    }

    // MARK: 목록

    func testTrainingSessionsCoverEveryKindInOrder() {
        XCTAssertEqual(sessions().count, TrainingSessionKind.allCases.count)
        XCTAssertEqual(sessions().map(\.id), TrainingSessionKind.allCases.map(\.templateId))
    }

    /// 기존 프리셋 API 를 깨지 않는다 — 세션은 별도 목록이다.
    func testPresetsListIsUnaffectedBySessions() {
        XCTAssertEqual(HyroxPresets.all.count, 9)
        let presetIds = Set(HyroxPresets.all.map(\.id))
        XCTAssertTrue(sessions().allSatisfy { !presetIds.contains($0.id) })
    }

    func testEverySessionValidatesAndIsBuiltIn() {
        for template in sessions() {
            XCTAssertNoThrow(try template.validate(), template.name)
            XCTAssertTrue(template.isBuiltIn, template.name)
            XCTAssertFalse(template.segments.isEmpty, template.name)
        }
    }

    /// 세션에 디비전을 달면 `TemplateGoalOverrideStore` 가 같은 디비전 프리셋의 목표를
    /// 덮어쓴다. 그래서 의도적으로 division 을 비워 둔다.
    func testSessionsCarryNoDivision() {
        for template in sessions(.womenProSingle) {
            XCTAssertNil(template.division, template.name)
        }
    }

    /// 요청할 때마다 새로 조립되지만 값은 같아야 한다 (화면 diff · 가민 전송).
    func testSessionsAreStableAcrossCalls() {
        XCTAssertEqual(sessions(.menProSingle), sessions(.menProSingle))
    }

    /// 세그먼트 ID 가 세션끼리, 그리고 템플릿 ID 와도 겹치면 안 된다.
    func testSegmentIdsAreUniqueAcrossSessions() {
        let templates = sessions()
        let segmentIds = templates.flatMap { $0.segments.map(\.id) }
        XCTAssertEqual(Set(segmentIds).count, segmentIds.count)
        XCTAssertTrue(Set(segmentIds).isDisjoint(with: Set(templates.map(\.id))))
    }

    /// 페이스 플래너 데이터는 8×1 km + 8 스테이션 경기 기준이라 세션에 적용하면 안 된다.
    func testNoSessionLooksLikeAStandardCourse() {
        for template in sessions() {
            XCTAssertFalse(template.isStandardHyroxCourse, template.name)
        }
    }

    // MARK: 세그먼트 구성

    func testCompromisedRunAlternatesKilometreRunsAndLunges() {
        let template = session(.compromisedRun)
        // 4 × [run, rox, station, rox] − 마지막 퇴장 rox
        XCTAssertEqual(template.segments.count, 15)
        XCTAssertTrue(template.usesRoxZone)
        XCTAssertEqual(runs(template).count, 4)
        XCTAssertEqual(stations(template).count, 4)
        XCTAssertTrue(runs(template).allSatisfy { $0.distanceMeters == 1000 })
        XCTAssertTrue(stations(template).allSatisfy { $0.stationKind == .sandbagLunges })
        XCTAssertEqual(template.segments.first?.type, .run)
        XCTAssertEqual(template.segments.last?.type, .station)
    }

    func testHalfSimulationMirrorsTheFirstHalfOfTheCourse() {
        let template = session(.halfSimulation)
        XCTAssertEqual(template.segments.count, 15)
        XCTAssertEqual(runs(template).count, 4)
        XCTAssertEqual(
            stations(template).compactMap(\.stationKind),
            Array(StationKind.standardOrder.prefix(4))
        )
        // 앞 절반은 대회 볼륨 그대로다.
        let specs = HyroxDivisionSpec.stations(for: .menOpenSingle).prefix(4)
        XCTAssertEqual(stations(template).compactMap(\.stationTarget), specs.map(\.target))
    }

    func testStationIntervalsRepeatThreeStationsWithoutRunning() {
        let template = session(.stationIntervals)
        XCTAssertEqual(template.segments.count, 9)
        XCTAssertFalse(template.usesRoxZone)
        XCTAssertTrue(runs(template).isEmpty)
        XCTAssertFalse(template.segments.contains { $0.type == .roxZone })
        let oneRound: [StationKind] = [.wallBalls, .burpeeBroadJumps, .sandbagLunges]
        let expected: [StationKind] = Array(repeating: oneRound, count: 3).flatMap { $0 }
        XCTAssertEqual(stations(template).compactMap(\.stationKind), expected)
        // 대회 볼륨의 절반씩.
        XCTAssertEqual(stations(template).first?.stationTarget, .reps(count: 50))
    }

    func testRoxZoneDrillUsesShortRunsAndFourEntries() {
        let template = session(.roxZoneDrill)
        XCTAssertEqual(template.segments.count, 15)
        XCTAssertTrue(template.usesRoxZone)
        XCTAssertEqual(template.segments.filter { $0.type == .roxZone }.count, 7)
        XCTAssertTrue(runs(template).allSatisfy { $0.distanceMeters == 400 })
        XCTAssertEqual(
            stations(template).compactMap(\.stationKind),
            [.skiErg, .burpeeBroadJumps, .farmersCarry, .wallBalls]
        )
        // 대회 볼륨의 1/4 — 진입 연습이 목적이라 짧게 끊는다.
        XCTAssertEqual(stations(template).first?.stationTarget, .distance(meters: 250))
        XCTAssertEqual(stations(template).last?.stationTarget, .reps(count: 25))
    }

    func testWallBallLadderSplitsTheRaceVolume() {
        for division in HyroxDivision.allCases {
            let template = session(.wallBallLadder, division)
            let sets = stations(template)
            XCTAssertEqual(sets.count, 5, division.rawValue)
            XCTAssertTrue(sets.allSatisfy { $0.stationKind == .wallBalls }, division.rawValue)

            let reps: [Int] = sets.compactMap {
                guard case .reps(let count) = $0.stationTarget else { return nil }
                return count
            }
            XCTAssertEqual(reps.count, 5, division.rawValue)
            // 내림차순 사다리, 합계는 대회 볼륨과 같다.
            XCTAssertEqual(reps, reps.sorted(by: >), division.rawValue)
            guard case .reps(let raceReps) = HyroxDivisionSpec.stations(for: division)
                .first(where: { $0.kind == .wallBalls })?.target
            else {
                XCTFail("wall balls target is not rep-based for \(division.rawValue)")
                continue
            }
            XCTAssertEqual(reps.reduce(0, +), raceReps, division.rawValue)
        }
    }

    // MARK: 디비전 반영

    func testWeightsComeFromTheDivisionSpec() {
        let menPro = session(.wallBallLadder, .menProSingle)
        let womenOpen = session(.wallBallLadder, .womenOpenSingle)
        XCTAssertTrue(stations(menPro).allSatisfy { $0.weightKg == 9 })
        XCTAssertTrue(stations(womenOpen).allSatisfy { $0.weightKg == 4 })

        // 무게는 볼륨과 달리 절대 줄이지 않는다.
        let lunges = session(.compromisedRun, .menProSingle)
        XCTAssertTrue(stations(lunges).allSatisfy { $0.weightKg == 30 })
        let sled = session(.halfSimulation, .womenProSingle)
        XCTAssertEqual(
            stations(sled).first(where: { $0.stationKind == .sledPush })?.weightKg,
            152
        )
    }

    func testStationGoalsShrinkWithVolume() {
        let full = session(.halfSimulation)
        let quarter = session(.roxZoneDrill)
        XCTAssertEqual(stations(full).first?.goalDurationSeconds, 240)
        XCTAssertEqual(stations(quarter).first?.goalDurationSeconds, 60)
    }

    // MARK: 지역화

    func testLocalizationKeysAreUniqueAndNamespaced() {
        let nameKeys = TrainingSessionKind.allCases.map(\.nameLocalizationKey)
        let summaryKeys = TrainingSessionKind.allCases.map(\.summaryLocalizationKey)

        XCTAssertEqual(Set(nameKeys).count, nameKeys.count)
        XCTAssertEqual(Set(summaryKeys).count, summaryKeys.count)
        XCTAssertTrue(Set(nameKeys).isDisjoint(with: Set(summaryKeys)))

        for key in nameKeys + summaryKeys {
            XCTAssertTrue(key.hasPrefix("training_session."), key)
            XCTAssertFalse(key.hasSuffix("."), key)
            XCTAssertFalse(key.contains(" "), key)
        }
    }

    func testNamesUseTheInjectedLocalizer() {
        let localized = HyroxPresets.trainingSessions(for: .menOpenSingle) { "L:\($0.rawValue)" }
        XCTAssertEqual(localized.map(\.name), TrainingSessionKind.allCases.map { "L:\($0.rawValue)" })
    }

    func testDefaultLocalizerFallsBackToEnglishNames() {
        XCTAssertEqual(sessions().map(\.name), TrainingSessionKind.allCases.map(\.defaultName))
        for kind in TrainingSessionKind.allCases {
            XCTAssertFalse(kind.defaultName.isEmpty, kind.rawValue)
            XCTAssertFalse(kind.defaultSummary.isEmpty, kind.rawValue)
        }
    }
}
