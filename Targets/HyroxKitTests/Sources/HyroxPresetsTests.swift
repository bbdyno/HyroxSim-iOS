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

// MARK: - PFT 벤치마크 템플릿

final class HyroxPFTBenchmarkTemplateTests: XCTestCase {

    private func template(_ division: HyroxDivision? = nil) -> WorkoutTemplate {
        HyroxPresets.pftBenchmark(for: division)
    }

    private func stations(_ template: WorkoutTemplate) -> [WorkoutSegment] {
        template.segments.filter { $0.type == .station }
    }

    /// 공식 프로토콜 순서·볼륨 그대로여야 한다.
    func testProtocolOrderAndVolume() {
        let segments = template().segments
        XCTAssertEqual(segments.count, 6)
        XCTAssertEqual(segments.map(\.type), [.run, .station, .station, .station, .station, .station])

        XCTAssertEqual(segments[0].distanceMeters, 1000)
        XCTAssertEqual(segments[1].stationKind, .burpeeBroadJumps)
        XCTAssertEqual(segments[1].stationTarget, .reps(count: 50))
        XCTAssertEqual(segments[2].stationKind, .sandbagLunges)
        XCTAssertEqual(segments[2].stationTarget, .distance(meters: 100))
        XCTAssertEqual(segments[3].stationKind, .rowing)
        XCTAssertEqual(segments[3].stationTarget, .distance(meters: 1000))
        XCTAssertEqual(segments[4].stationTarget, .reps(count: 30))
        XCTAssertEqual(segments[5].stationKind, .wallBalls)
        XCTAssertEqual(segments[5].stationTarget, .reps(count: 100))
    }

    /// 푸시업은 대회에 없는 종목이라 커스텀으로 들어간다 — 이름은 호출자가 지역화한다.
    func testPushUpsAreACustomStationWithTheInjectedName() {
        let localized = HyroxPresets.pftBenchmark(stepName: { "L:\($0.rawValue)" })
        XCTAssertEqual(localized.segments[4].stationKind, .custom(name: "L:pushUps"))
        // 대회에 있는 종목은 커스텀으로 바뀌지 않는다.
        XCTAssertEqual(localized.segments[5].stationKind, .wallBalls)
        XCTAssertEqual(template().segments[4].stationKind, .custom(name: PFTStep.pushUps.defaultName))
    }

    /// PFT 는 이어서 하는 한 덩어리다 — 전환 구간을 넣으면 기록이 실제와 달라진다.
    func testPFTHasNoRoxZones() {
        XCTAssertFalse(template().usesRoxZone)
        XCTAssertFalse(template().segments.contains { $0.type == .roxZone })
    }

    func testPFTIsBuiltInWithoutDivisionAndValidates() {
        XCTAssertTrue(template().isBuiltIn)
        // 디비전을 달면 `TemplateGoalOverrideStore` 가 같은 디비전 프리셋 목표를 덮어쓴다.
        XCTAssertNil(template().division)
        XCTAssertNil(template(.menProSingle).division)
        XCTAssertNoThrow(try template().validate())
    }

    /// 월볼 무게만 디비전을 따른다. 나머지는 맨몸이거나 기구가 정해져 있다.
    func testWallBallWeightFollowsDivisionOnly() {
        XCTAssertNil(template().segments.last?.weightKg)
        XCTAssertEqual(template(.menProSingle).segments.last?.weightKg, 9)
        XCTAssertEqual(template(.womenOpenSingle).segments.last?.weightKg, 4)
        XCTAssertTrue(stations(template(.menProSingle)).dropLast().allSatisfy { $0.weightKg == nil })
    }

    /// 기본 목표 합계는 보도 기준 구간(15–35분) 한가운데다.
    func testDefaultGoalsLandInTheMiddleOfTheReportedBand() {
        let total = template().estimatedDurationSeconds
        XCTAssertEqual(total, 1305, accuracy: 0.001)
        XCTAssertGreaterThan(total, PFTBenchmarkEvaluator.reportedFastestSeconds)
        XCTAssertLessThan(total, PFTBenchmarkEvaluator.reportedSlowestSeconds)
    }

    /// 요청할 때마다 새로 조립되지만 값은 같아야 한다 (화면 diff · 가민 전송).
    func testTemplateIsStableAcrossCalls() {
        XCTAssertEqual(template(.menOpenSingle), template(.menOpenSingle))
        XCTAssertEqual(template().id, PFTBenchmark.templateId)
        XCTAssertEqual(
            template().segments.map(\.id),
            (0..<6).map { PFTBenchmark.segmentId(at: $0) }
        )
    }

    /// 대회 프리셋과 ID 가 겹치면 안 된다.
    /// PFT 는 훈련 세션 목록의 한 항목이므로, 세션 중에서는 자기 자신만 같은 ID 를 갖는다.
    func testIdsDoNotCollideWithPresetsOrSessions() {
        XCTAssertEqual(HyroxPresets.all.count, 9)
        XCTAssertFalse(Set(HyroxPresets.all.map(\.id)).contains(PFTBenchmark.templateId))

        let otherSessions = HyroxPresets.trainingSessions(for: .menOpenSingle)
            .filter { $0.id != PFTBenchmark.templateId }
        XCTAssertEqual(otherSessions.count, TrainingSessionKind.allCases.count - 1)
        XCTAssertFalse(Set(otherSessions.map(\.id)).contains(PFTBenchmark.templateId))

        let otherSegmentIds = Set(otherSessions.flatMap { $0.segments.map(\.id) })
        XCTAssertTrue(otherSegmentIds.isDisjoint(with: Set(template().segments.map(\.id))))
    }

    /// 페이스 플래너 데이터는 8×1 km + 8 스테이션 경기 기준이라 PFT 에 적용하면 안 된다.
    func testPFTIsNotAStandardCourse() {
        XCTAssertFalse(template().isStandardHyroxCourse)
    }

    func testStepLocalizationKeysAreUniqueAndNamespaced() {
        let keys = PFTStep.allCases.map(\.nameLocalizationKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        for key in keys + [PFTBenchmark.nameLocalizationKey, PFTBenchmark.summaryLocalizationKey] {
            XCTAssertTrue(key.hasPrefix("pft."), key)
            XCTAssertFalse(key.hasSuffix("."), key)
            XCTAssertFalse(key.contains(" "), key)
        }
    }
}

// MARK: - 릴레이 구간 템플릿

final class HyroxRelayLegTests: XCTestCase {

    private func stations(_ template: WorkoutTemplate) -> [StationKind] {
        template.segments.compactMap { $0.type == .station ? $0.stationKind : nil }
    }

    /// 1인당 2 × (1 km + 스테이션).
    func testLegIsTwoRunStationRounds() {
        let leg = HyroxPresets.relayLeg(slot: 0, division: .men)
        XCTAssertEqual(leg.segments.count, 7) // run, rox, station, rox, run, rox, station
        XCTAssertTrue(leg.usesRoxZone)
        XCTAssertEqual(leg.segments.filter { $0.type == .run }.count, 2)
        XCTAssertEqual(leg.segments.filter { $0.type == .station }.count, 2)
        XCTAssertTrue(leg.segments.filter { $0.type == .run }.allSatisfy { $0.distanceMeters == 1000 })
        XCTAssertNoThrow(try leg.validate())
        XCTAssertNil(leg.division)
        XCTAssertTrue(leg.isBuiltIn)
    }

    /// 순번대로 돌면 4명이 8개 스테이션을 정확히 두 개씩 나눠 갖는다.
    func testFourLegsCoverEveryStationExactlyOnce() {
        let legs = HyroxPresets.relayLegs(for: .women)
        XCTAssertEqual(legs.count, 4)

        let covered = legs.flatMap { stations($0) }
        XCTAssertEqual(covered.count, 8)
        XCTAssertEqual(Set(covered), Set(StationKind.standardOrder))
        XCTAssertEqual(stations(legs[0]), [.skiErg, .rowing])
        XCTAssertEqual(stations(legs[3]), [.burpeeBroadJumps, .wallBalls])
    }

    /// 릴레이 무게는 성별 Open 을 따른다. 혼성은 슬롯마다 자기 성별 Open 이다.
    func testWeightsFollowTheGenderOpenDivision() {
        let menSled = HyroxPresets.relayLeg(slot: 1, division: .men)
            .segments.first { $0.stationKind == .sledPush }
        XCTAssertEqual(menSled?.weightKg, 152)

        let womenSled = HyroxPresets.relayLeg(slot: 1, division: .women)
            .segments.first { $0.stationKind == .sledPush }
        XCTAssertEqual(womenSled?.weightKg, 102)

        // 혼성 기본 배치: 슬롯 0·1 여자, 2·3 남자.
        let mixedWomenSled = HyroxPresets.relayLeg(slot: 1, division: .mixed)
            .segments.first { $0.stationKind == .sledPush }
        XCTAssertEqual(mixedWomenSled?.weightKg, 102)
        let mixedMenPull = HyroxPresets.relayLeg(slot: 2, division: .mixed)
            .segments.first { $0.stationKind == .sledPull }
        XCTAssertEqual(mixedMenPull?.weightKg, 103)
    }

    func testLegIdsAreStableAndUnique() {
        let legs = HyroxPresets.relayLegs(for: .men)
        XCTAssertEqual(legs, HyroxPresets.relayLegs(for: .men))

        let templateIds = Set(legs.map(\.id))
        XCTAssertEqual(templateIds.count, 4)
        XCTAssertFalse(templateIds.contains(PFTBenchmark.templateId))

        let segmentIds = legs.flatMap { $0.segments.map(\.id) }
        XCTAssertEqual(Set(segmentIds).count, segmentIds.count)
        XCTAssertTrue(Set(segmentIds).isDisjoint(with: templateIds))
    }

    /// 슬롯을 벗어난 값이 들어와도 팀 안에서 한 바퀴 돌 뿐 터지지 않는다.
    func testOutOfRangeSlotWrapsAround() {
        XCTAssertEqual(
            HyroxPresets.relayLeg(slot: 4, division: .men),
            HyroxPresets.relayLeg(slot: 0, division: .men)
        )
        XCTAssertEqual(
            HyroxPresets.relayLeg(slot: -1, division: .men),
            HyroxPresets.relayLeg(slot: 3, division: .men)
        )
    }
}

// MARK: - 더블스·릴레이 분담

final class TeamSplitPlanTests: XCTestCase {

    /// 보기 좋은 숫자로 맞춘 표: 목표 4500초 = 러닝+록스존 3500 + 스테이션 8 × 125.
    private let goalSeconds = 4500

    private func reference(_ entry: TeamEntry, goal: Int? = nil) -> TeamSplitReference {
        TeamSplitReference.make(
            entry: entry,
            dataset: PaceDatasetFixture.make(divisionKey: entry.referenceDivision.rawValue),
            goalSeconds: goal ?? goalSeconds
        )
    }

    private func result(_ plan: TeamSplitPlan) -> TeamSplitResult {
        TeamSplitCalculator.result(for: plan, reference: reference(plan.entry))
    }

    // MARK: 기준 구성

    /// 구성 합은 언제나 목표와 정확히 같다 — 반올림이 새면 화면의 합계가 목표와 어긋난다.
    func testReferenceComponentsAddUpToTheGoal() {
        for goal in [3000, 4500, 5400, 7200] {
            let value = reference(.doubles(.menOpenDouble), goal: goal)
            XCTAssertEqual(
                value.runRoxSeconds + value.stationTotalSeconds,
                TimeInterval(goal),
                accuracy: 0.001,
                "goal \(goal)"
            )
            XCTAssertEqual(value.totalSeconds, TimeInterval(goal), accuracy: 0.001)
        }
    }

    func testReferenceReadsTheDoublesTableWhenItCoversTheGoal() {
        let value = reference(.doubles(.menOpenDouble))
        XCTAssertFalse(value.isEstimated)
        XCTAssertEqual(value.runRoxSeconds, 3500, accuracy: 0.001)
        XCTAssertEqual(value.seconds(for: .wallBalls), 125, accuracy: 0.001)
        XCTAssertEqual(value.stationTotalSeconds, 1000, accuracy: 0.001)
    }

    /// 표 밖의 목표와 릴레이는 비율로 늘린 값이라 항상 추정으로 표시한다.
    func testOutOfRangeGoalsAndRelayAreMarkedEstimated() {
        XCTAssertTrue(reference(.doubles(.menOpenDouble), goal: 2400).isEstimated)
        XCTAssertTrue(reference(.relay(.men)).isEstimated)
    }

    /// 목표를 늘리면 모든 구간이 같이 늘어난다(단조).
    func testScalingIsMonotone() {
        let slower = reference(.relay(.men), goal: 5400)
        let faster = reference(.relay(.men), goal: 3600)
        XCTAssertGreaterThan(slower.runRoxSeconds, faster.runRoxSeconds)
        for station in StationKind.standardOrder {
            XCTAssertGreaterThan(slower.seconds(for: station), faster.seconds(for: station), "\(station)")
        }
    }

    // MARK: 더블스

    func testDoublesDefaultsToFiftyFifty() {
        let plan = TeamSplitPlan.balanced(
            entry: .doubles(.menOpenDouble),
            goalTotalSeconds: TimeInterval(goalSeconds)
        )
        XCTAssertTrue(plan.isBalanced)
        XCTAssertEqual(plan.memberCount, 2)
        for index in 0..<TeamSplitPlan.stationCount {
            XCTAssertEqual(plan.share(stationAt: index, slot: 0), 0.5, accuracy: 0.0001)
            XCTAssertEqual(plan.share(stationAt: index, slot: 1), 0.5, accuracy: 0.0001)
        }

        let value = result(plan)
        XCTAssertEqual(value.members.count, 2)
        XCTAssertEqual(value.members[0].stationSeconds, 500, accuracy: 0.001)
        XCTAssertEqual(value.members[1].stationSeconds, 500, accuracy: 0.001)
        XCTAssertEqual(value.imbalanceSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(value.peakStationShare, 0.5, accuracy: 0.0001)
    }

    /// 런은 나누지 않는다 — 함께 뛰어야 하므로 누구의 몫도 아니다.
    func testDoublesRunningIsSharedNotSplit() {
        let value = result(.balanced(entry: .doubles(.mixedDouble), goalTotalSeconds: TimeInterval(goalSeconds)))
        XCTAssertEqual(value.sharedRunRoxSeconds, 3500, accuracy: 0.001)
        XCTAssertTrue(value.members.allSatisfy { $0.runSeconds == 0 })
        // 파트너가 스테이션을 처리하는 동안이 곧 휴식이다.
        XCTAssertEqual(value.members[0].restSeconds, 500, accuracy: 0.001)
    }

    /// 한쪽으로 몰면 그 사람 부하만 늘고, 팀 합계는 그대로다.
    func testSkewedSplitMovesLoadWithoutChangingTheTotal() {
        let balanced = TeamSplitPlan.balanced(
            entry: .doubles(.menOpenDouble),
            goalTotalSeconds: TimeInterval(goalSeconds)
        )
        // 슬레드 푸시(스테이션 2번)를 A 가 80 % 맡는다.
        let skewed = balanced.settingShare(0.8, stationAt: 1, slot: 0)

        XCTAssertFalse(skewed.isBalanced)
        XCTAssertEqual(skewed.share(stationAt: 1, slot: 0), 0.8, accuracy: 0.0001)
        XCTAssertEqual(skewed.share(stationAt: 1, slot: 1), 0.2, accuracy: 0.0001)
        // 건드리지 않은 스테이션은 그대로 50 : 50.
        XCTAssertEqual(skewed.share(stationAt: 0, slot: 0), 0.5, accuracy: 0.0001)

        let value = result(skewed)
        XCTAssertEqual(value.members[0].stationSeconds, 537.5, accuracy: 0.001)
        XCTAssertEqual(value.members[1].stationSeconds, 462.5, accuracy: 0.001)
        XCTAssertEqual(value.imbalanceSeconds, 75, accuracy: 0.001)
        XCTAssertEqual(value.teamStationSeconds, 1000, accuracy: 0.001)
        XCTAssertEqual(value.projectedTotalSeconds, TimeInterval(goalSeconds), accuracy: 0.001)
    }

    /// 한 명이 전부 맡아도 합계는 변하지 않는다 — 달라지는 건 누가 하느냐뿐이다.
    func testOneSidedSplitKeepsTheTeamTotal() {
        var plan = TeamSplitPlan.balanced(
            entry: .doubles(.menOpenDouble),
            goalTotalSeconds: TimeInterval(goalSeconds)
        )
        for index in 0..<TeamSplitPlan.stationCount {
            plan = plan.settingShare(1, stationAt: index, slot: 0)
        }

        let value = result(plan)
        XCTAssertEqual(value.members[0].stationSeconds, 1000, accuracy: 0.001)
        XCTAssertEqual(value.members[1].stationSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(value.peakStationShare, 1, accuracy: 0.0001)
        XCTAssertEqual(value.projectedTotalSeconds, TimeInterval(goalSeconds), accuracy: 0.001)
        XCTAssertTrue(value.members[1].stations.isEmpty)
    }

    func testResetRestoresTheBalancedSplit() {
        let plan = TeamSplitPlan
            .balanced(entry: .doubles(.womenProDouble), goalTotalSeconds: TimeInterval(goalSeconds))
            .settingShare(0.9, stationAt: 3, slot: 0)
        XCTAssertFalse(plan.isBalanced)
        XCTAssertTrue(plan.resettingToBalanced().isBalanced)
    }

    // MARK: 릴레이

    /// 4명이 두 구간씩, 런도 함께 나눠 갖는다.
    func testRelaySplitsEightLegsAcrossFourAthletes() {
        let plan = TeamSplitPlan.balanced(
            entry: .relay(.mixed),
            goalTotalSeconds: TimeInterval(goalSeconds)
        )
        XCTAssertEqual(plan.memberCount, 4)
        XCTAssertEqual((0..<TeamSplitPlan.stationCount).compactMap { plan.owner(stationAt: $0) }, [0, 1, 2, 3, 0, 1, 2, 3])

        let value = result(plan)
        XCTAssertEqual(value.members.count, 4)
        XCTAssertEqual(value.sharedRunRoxSeconds, 0, accuracy: 0.001)
        for member in value.members {
            XCTAssertEqual(member.stations.count, 2, member.name)
            XCTAssertEqual(member.stationSeconds, 250, accuracy: 0.001, member.name)
            // 1인당 2 × (1 km + 전환) = 3500 / 8 × 2.
            XCTAssertEqual(member.runSeconds, 875, accuracy: 0.001, member.name)
            XCTAssertEqual(member.totalSeconds, 1125, accuracy: 0.001, member.name)
        }
        XCTAssertEqual(value.members.reduce(0) { $0 + $1.runSeconds }, 3500, accuracy: 0.001)
        XCTAssertEqual(value.teamStationSeconds, 1000, accuracy: 0.001)
        XCTAssertEqual(value.projectedTotalSeconds, TimeInterval(goalSeconds), accuracy: 0.001)
        XCTAssertEqual(value.imbalanceSeconds, 0, accuracy: 0.001)
    }

    /// 구간을 다른 사람에게 넘기면 런까지 함께 넘어간다.
    func testReassigningALegMovesItsRunningToo() {
        let plan = TeamSplitPlan
            .balanced(entry: .relay(.men), goalTotalSeconds: TimeInterval(goalSeconds))
            .assigning(stationAt: 0, to: 1)

        XCTAssertEqual(plan.owner(stationAt: 0), 1)
        let value = result(plan)
        XCTAssertEqual(value.members[0].stations.count, 1)
        XCTAssertEqual(value.members[1].stations.count, 3)
        XCTAssertEqual(value.members[0].runSeconds, 437.5, accuracy: 0.001)
        XCTAssertEqual(value.members[1].runSeconds, 1312.5, accuracy: 0.001)
        // 넘겨도 팀 합계는 그대로.
        XCTAssertEqual(value.members.reduce(0) { $0 + $1.runSeconds }, 3500, accuracy: 0.001)
        XCTAssertEqual(value.teamStationSeconds, 1000, accuracy: 0.001)
    }

    // MARK: 불변식

    /// 어떤 분담이든 사람별 합은 팀 합과 같다.
    func testMemberLoadsAlwaysSumToTheTeamTotal() {
        let entries: [TeamEntry] = [.doubles(.menOpenDouble), .relay(.women)]
        for entry in entries {
            var plan = TeamSplitPlan.balanced(entry: entry, goalTotalSeconds: TimeInterval(goalSeconds))
            plan = plan.settingShare(0.7, stationAt: 2, slot: 0)
            plan = plan.settingShare(0.1, stationAt: 5, slot: 0)

            let value = result(plan)
            let stationSum = value.members.reduce(0) { $0 + $1.stationSeconds }
            let runSum = value.members.reduce(0) { $0 + $1.runSeconds }
            XCTAssertEqual(stationSum, value.reference.stationTotalSeconds, accuracy: 0.001, "\(entry)")
            XCTAssertEqual(
                runSum + value.sharedRunRoxSeconds,
                value.reference.runRoxSeconds,
                accuracy: 0.001,
                "\(entry)"
            )
            XCTAssertEqual(
                value.projectedTotalSeconds,
                TimeInterval(goalSeconds),
                accuracy: 0.001,
                "\(entry)"
            )
        }
    }

    /// 어떤 값이 들어와도 한 스테이션의 비율 합은 1 이다.
    func testSharesAreAlwaysNormalized() {
        let broken: [[Double]] = [
            [-5, 2],
            [0, 0],
            [.nan, 1],
            [3],
            [0.25, 0.25, 0.25, 0.25]
        ]
        let plan = TeamSplitPlan(
            entry: .doubles(.menOpenDouble),
            goalTotalSeconds: 4500,
            stationShares: broken
        )
        XCTAssertEqual(plan.stationShares.count, TeamSplitPlan.stationCount)
        for row in plan.stationShares {
            XCTAssertEqual(row.count, 2)
            XCTAssertEqual(row.reduce(0, +), 1, accuracy: 0.0001)
            XCTAssertTrue(row.allSatisfy { $0 >= 0 && $0 <= 1 })
        }
        // 값이 하나도 없던 행은 균등 분배로 떨어진다.
        XCTAssertEqual(plan.share(stationAt: 1, slot: 0), 0.5, accuracy: 0.0001)
    }

    /// 범위를 벗어난 비율은 잘라서 받는다.
    func testShareIsClampedToZeroAndOne() {
        let plan = TeamSplitPlan
            .balanced(entry: .doubles(.menOpenDouble), goalTotalSeconds: 4500)
            .settingShare(9, stationAt: 0, slot: 0)
        XCTAssertEqual(plan.share(stationAt: 0, slot: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(plan.share(stationAt: 0, slot: 1), 0, accuracy: 0.0001)
    }

    /// 저장·복원을 거쳐도 불변식이 유지된다.
    func testCodableRoundTripKeepsInvariants() throws {
        let plan = TeamSplitPlan
            .balanced(entry: .relay(.mixed), goalTotalSeconds: 4200)
            .assigning(stationAt: 7, to: 0)

        let data = try JSONEncoder().encode(plan)
        let restored = try JSONDecoder().decode(TeamSplitPlan.self, from: data)

        XCTAssertEqual(restored, plan)
        XCTAssertEqual(restored.entry, .relay(.mixed))
        XCTAssertEqual(restored.owner(stationAt: 7), 0)
        for row in restored.stationShares {
            XCTAssertEqual(row.reduce(0, +), 1, accuracy: 0.0001)
        }
    }

    /// 더블스 디비전 판정과 상대 디비전 찾기.
    func testDoublesHelpers() {
        XCTAssertTrue(HyroxDivision.mixedDouble.isDoubles)
        XCTAssertTrue(HyroxDivision.womenProDouble.isDoubles)
        XCTAssertFalse(HyroxDivision.menOpenSingle.isDoubles)
        XCTAssertEqual(HyroxDivision.menProSingle.doublesCounterpart, .menProDouble)
        XCTAssertEqual(HyroxDivision.mixedDouble.doublesCounterpart, .mixedDouble)
        XCTAssertEqual(RelayDivision(matching: .womenProSingle), .women)
        XCTAssertEqual(RelayDivision(matching: .mixedDouble), .mixed)
    }
}

// MARK: - PFT 해석

final class PFTBenchmarkEvaluatorTests: XCTestCase {

    private func evaluate(
        _ seconds: TimeInterval,
        dataset: PaceDataset = PaceDatasetFixture.make(),
        steps: [PFTStep: TimeInterval] = [:]
    ) -> PFTBenchmarkResult {
        PFTBenchmarkEvaluator.evaluate(
            totalSeconds: seconds,
            projectionDivision: .menOpenSingle,
            dataset: dataset,
            stepSeconds: steps
        )
    }

    // MARK: 등급 경계

    /// 보도 기준 경계는 25:00. 정각은 Pro 쪽이다.
    func testDivisionBoundaryIsTwentyFiveMinutes() {
        XCTAssertEqual(PFTBenchmarkEvaluator.recommendedDivision(forTotalSeconds: 1499), .pro)
        XCTAssertEqual(PFTBenchmarkEvaluator.recommendedDivision(forTotalSeconds: 1500), .pro)
        XCTAssertEqual(PFTBenchmarkEvaluator.recommendedDivision(forTotalSeconds: 1501), .open)
        XCTAssertEqual(PFTBenchmarkEvaluator.recommendedDivision(forTotalSeconds: 600), .pro)
        XCTAssertEqual(PFTBenchmarkEvaluator.recommendedDivision(forTotalSeconds: 3000), .open)
    }

    func testReportedBandEdges() {
        XCTAssertTrue(PFTBenchmarkEvaluator.isOutsideReportedBand(899))
        XCTAssertFalse(PFTBenchmarkEvaluator.isOutsideReportedBand(900))
        XCTAssertFalse(PFTBenchmarkEvaluator.isOutsideReportedBand(2100))
        XCTAssertTrue(PFTBenchmarkEvaluator.isOutsideReportedBand(2101))
    }

    /// 권장 등급은 같은 성별·포맷 안에서만 움직인다.
    func testRecommendedDivisionKeepsGenderAndFormat() {
        XCTAssertEqual(PFTRecommendedDivision.pro.division(matching: .menOpenSingle), .menProSingle)
        XCTAssertEqual(PFTRecommendedDivision.open.division(matching: .menProDouble), .menOpenDouble)
        XCTAssertEqual(PFTRecommendedDivision.pro.division(matching: .womenOpenDouble), .womenProDouble)
        // 혼성 더블스에는 Pro/Open 구분이 없다.
        XCTAssertEqual(PFTRecommendedDivision.pro.division(matching: .mixedDouble), .mixedDouble)
        XCTAssertEqual(PFTRecommendedDivision.open.division(matching: .mixedDouble), .mixedDouble)
    }

    // MARK: 예상 범위

    func testProjectedRangeSurroundsTheMappedFinishTime() {
        let result = evaluate(1500)
        XCTAssertEqual(result.projectedFinishRange.lowerBound, 4145)
        XCTAssertEqual(result.projectedFinishRange.upperBound, 4675)
        XCTAssertTrue(result.projectedPercentileRange.contains(46), "\(result.projectedPercentileRange)")
        XCTAssertEqual(result.projectionDivision, .menOpenSingle)
    }

    /// 느린 PFT 가 더 빠른 예상을 내면 안 된다 — 두 끝 모두 단조.
    func testProjectedRangeIsMonotoneInPFTTime() {
        var previous: ClosedRange<Int>?
        for seconds in stride(from: 300.0, through: 3000.0, by: 30.0) {
            let range = evaluate(seconds).projectedFinishRange
            if let previous {
                XCTAssertGreaterThanOrEqual(range.lowerBound, previous.lowerBound, "\(seconds)s")
                XCTAssertGreaterThanOrEqual(range.upperBound, previous.upperBound, "\(seconds)s")
            }
            previous = range
        }
        XCTAssertNotNil(previous)
        // 양 끝에서 실제로 움직였는지도 확인 — 전부 같은 값이면 단조는 공허하게 참이다.
        XCTAssertLessThan(
            evaluate(900).projectedFinishRange.upperBound,
            evaluate(2100).projectedFinishRange.upperBound
        )
    }

    /// 보도 밴드를 벗어나면 근거가 없으므로 범위를 더 넓게 준다.
    func testRangeWidensOutsideTheReportedBand() {
        func relativeSpread(_ result: PFTBenchmarkResult) -> Double {
            let middle = Double(result.projectedFinishRange.lowerBound + result.projectedFinishRange.upperBound) / 2
            guard middle > 0 else { return 0 }
            return Double(result.projectedSpreadSeconds) / middle
        }

        let inside = evaluate(1200)
        let below = evaluate(600)
        let above = evaluate(2700)

        XCTAssertFalse(inside.isOutsideReportedBand)
        XCTAssertTrue(below.isOutsideReportedBand)
        XCTAssertTrue(above.isOutsideReportedBand)
        XCTAssertGreaterThan(relativeSpread(below), relativeSpread(inside))
        XCTAssertGreaterThan(relativeSpread(above), relativeSpread(inside))
    }

    func testEstimatedPercentileIsClampedToTheReportedBand() {
        XCTAssertEqual(PFTBenchmarkEvaluator.estimatedPercentile(forTotalSeconds: 300), 2, accuracy: 0.0001)
        XCTAssertEqual(PFTBenchmarkEvaluator.estimatedPercentile(forTotalSeconds: 1500), 46, accuracy: 0.0001)
        XCTAssertEqual(PFTBenchmarkEvaluator.estimatedPercentile(forTotalSeconds: 3600), 90, accuracy: 0.0001)
    }

    // MARK: 구간 비교

    /// 대회와 볼륨이 같은 구간만 비교한다.
    func testOnlyComparableStepsGetAPercentile() {
        let result = evaluate(1500, steps: [
            .run: 437.5,
            .burpeeBroadJumps: 300,
            .lunges: 200,
            .row: 125,
            .pushUps: 90,
            .wallBalls: 100
        ])

        XCTAssertEqual(result.stepComparisons.map(\.step), [.run, .row, .wallBalls])
        XCTAssertEqual(result.stepComparisons[0].percentile, 50, accuracy: 0.0001) // 8바퀴 평균 기준
        XCTAssertTrue(result.stepComparisons[0].isApproximate)
        XCTAssertEqual(result.stepComparisons[1].percentile, 50, accuracy: 0.0001)
        XCTAssertFalse(result.stepComparisons[1].isApproximate)
        XCTAssertEqual(result.stepComparisons[2].percentile, 10, accuracy: 0.0001)
    }

    func testNoStepTimesMeansNoComparisons() {
        XCTAssertTrue(evaluate(1500).stepComparisons.isEmpty)
    }

    /// 곡선이 단조가 아니면(표본이 적은 구간) 답하지 않는다 — 거짓 등수를 만들지 않는다.
    func testFlatCurveIsSkipped() {
        let dataset = PaceDatasetFixture.make(
            stationsS: PaceDatasetFixture.stations(overriding: "rowing", with: [120, 120, 120])
        )
        let result = evaluate(1500, dataset: dataset, steps: [.row: 120, .wallBalls: 125])
        XCTAssertEqual(result.stepComparisons.map(\.step), [.wallBalls])
    }
}

// MARK: - PFT 기록 판별

@MainActor
final class PFTBenchmarkRecordTests: XCTestCase {

    private var t0: Date { Date(timeIntervalSinceReferenceDate: 0) }

    /// PFT 템플릿을 끝까지 돌린 기록.
    private func makePFTWorkout(
        stepDurations: [TimeInterval] = [300, 260, 200, 240, 100, 300]
    ) throws -> CompletedWorkout {
        let engine = WorkoutEngine(template: HyroxPresets.pftBenchmark())
        try engine.start(at: t0)
        var elapsed: TimeInterval = 0
        for duration in stepDurations {
            elapsed += duration
            try engine.advance(at: t0.addingTimeInterval(elapsed))
        }
        return try engine.makeCompletedWorkout()
    }

    private func makeRaceWorkout() throws -> CompletedWorkout {
        let template = HyroxPresets.template(for: .menOpenSingle)
        let engine = WorkoutEngine(template: template)
        try engine.start(at: t0)
        for index in 1...template.segments.count {
            try engine.advance(at: t0.addingTimeInterval(TimeInterval(index) * 60))
        }
        return try engine.makeCompletedWorkout()
    }

    func testPFTWorkoutIsRecognisedAndTimed() throws {
        let workout = try makePFTWorkout()
        XCTAssertTrue(PFTBenchmark.isRecord(workout))
        XCTAssertEqual(try XCTUnwrap(PFTBenchmark.totalSeconds(of: workout)), 1400, accuracy: 0.001)

        let steps = PFTBenchmark.stepSeconds(of: workout)
        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(steps[.run], 300)
        XCTAssertEqual(steps[.lunges], 200)
        XCTAssertEqual(steps[.pushUps], 100)
        XCTAssertEqual(steps[.wallBalls], 300)
    }

    /// 대회 기록은 PFT 가 아니다.
    func testRaceWorkoutIsNotAPFTRecord() throws {
        let workout = try makeRaceWorkout()
        XCTAssertFalse(PFTBenchmark.isRecord(workout))
        XCTAssertNil(PFTBenchmark.totalSeconds(of: workout))
        XCTAssertTrue(PFTBenchmark.stepSeconds(of: workout).isEmpty)
    }

    /// 워치·가민을 거치며 ID 가 달라진 기록도 코스 모양으로 알아본다.
    func testRecordWithForeignSegmentIdsIsStillRecognised() throws {
        let original = try makePFTWorkout()
        let renumbered = CompletedWorkout(
            templateName: original.templateName,
            division: original.division,
            startedAt: original.startedAt,
            finishedAt: original.finishedAt,
            segments: original.segments.map { record in
                SegmentRecord(
                    segmentId: UUID(),
                    index: record.index,
                    type: record.type,
                    startedAt: record.startedAt,
                    endedAt: record.endedAt,
                    stationDisplayName: record.stationDisplayName,
                    plannedDistanceMeters: record.plannedDistanceMeters,
                    goalDurationSeconds: record.goalDurationSeconds
                )
            }
        )
        XCTAssertTrue(PFTBenchmark.isRecord(renumbered))
    }

    func testMostRecentRecordPicksTheLatestPFT() throws {
        let older = try makePFTWorkout()
        let newer = CompletedWorkout(
            templateName: older.templateName,
            division: nil,
            startedAt: older.startedAt.addingTimeInterval(86_400),
            finishedAt: older.finishedAt.addingTimeInterval(86_400),
            segments: older.segments
        )
        let race = try makeRaceWorkout()

        XCTAssertEqual(PFTBenchmark.mostRecentRecord(in: [older, race, newer])?.id, newer.id)
        XCTAssertNil(PFTBenchmark.mostRecentRecord(in: [race]))
    }
}
