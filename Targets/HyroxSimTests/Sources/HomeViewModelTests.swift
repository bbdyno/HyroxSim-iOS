//
//  HomeViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 4/7/26.
//

import XCTest
import HyroxCore
import HyroxPersistenceApple
@testable import HyroxSim

@MainActor
final class HomeViewModelTests: XCTestCase {

    private func makePersistence() throws -> PersistenceController {
        try PersistenceController(inMemory: true)
    }

    func testLoadPresetsCount() throws {
        let vm = HomeViewModel(persistence: try makePersistence())
        vm.load()
        XCTAssertEqual(vm.presets.count, 9)
    }

    func testEmptyRecentWorkouts() throws {
        let vm = HomeViewModel(persistence: try makePersistence())
        vm.load()
        XCTAssertTrue(vm.recentWorkouts.isEmpty)
        XCTAssertNil(vm.mostRecentWorkout)
    }

    func testRecentWorkoutAfterSave() throws {
        let persistence = try makePersistence()
        let workout = CompletedWorkout(
            templateName: "Test",
            startedAt: Date(),
            finishedAt: Date().addingTimeInterval(600),
            segments: []
        )
        try persistence.saveCompletedWorkout(workout)

        let vm = HomeViewModel(persistence: persistence)
        vm.load()
        XCTAssertEqual(vm.recentWorkouts.count, 1)
        XCTAssertNotNil(vm.mostRecentWorkout)
        XCTAssertEqual(vm.mostRecentWorkout?.id, workout.id)
    }

    // MARK: - 진척 화면 진입점

    /// 기록이 하나도 없으면 진척 화면은 "아직 없다"는 말밖에 못 한다 — 홈에서 감춘다.
    func testProgressEntryIsHiddenWithoutAnyRecord() throws {
        let vm = HomeViewModel(persistence: try makePersistence())
        vm.load()
        XCTAssertFalse(vm.showsProgressEntry)
    }

    func testProgressEntryAppearsAfterTheFirstRecord() throws {
        let persistence = try makePersistence()
        try persistence.saveCompletedWorkout(
            CompletedWorkout(
                templateName: "Race Simulation",
                division: .menOpenSingle,
                startedAt: Date(),
                finishedAt: Date().addingTimeInterval(5_400),
                segments: []
            )
        )

        let vm = HomeViewModel(persistence: persistence)
        vm.load()
        XCTAssertTrue(vm.showsProgressEntry)
    }
}

// MARK: - 내 대회 카드

@MainActor
final class HomeViewModelRaceTargetTests: XCTestCase {

    /// 기기 시간대와 무관하게 D-day 를 검증하려고 UTC 달력을 주입한다.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private lazy var today: Date = {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 9)) ?? Date()
    }()

    private func makeViewModel(_ persistence: PersistenceController) -> HomeViewModel {
        HomeViewModel(
            persistence: persistence,
            goalOverrideStore: TemplateGoalOverrideStore(defaults: throwawayDefaults()),
            calendar: calendar,
            now: { self.today }
        )
    }

    private func throwawayDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.hyroxsim.tests.home.\(UUID().uuidString)") ?? .standard
    }

    private func date(offsetDays: Int) -> Date {
        calendar.date(byAdding: .day, value: offsetDays, to: today) ?? today
    }

    func testNoRaceTargetMeansNoCountdown() throws {
        let vm = makeViewModel(try PersistenceController(inMemory: true))
        vm.load()
        XCTAssertNil(vm.raceCountdown)
    }

    func testUpcomingRaceShowsDMinusDays() throws {
        let persistence = try PersistenceController(inMemory: true)
        try persistence.upsertRaceTarget(
            RaceTarget(
                eventName: "HYROX Seoul",
                city: "Seoul",
                date: date(offsetDays: 7),
                division: .womenProSingle,
                goalDurationSeconds: 5_400
            )
        )

        let vm = makeViewModel(persistence)
        vm.load()

        let countdown = try XCTUnwrap(vm.raceCountdown)
        XCTAssertEqual(countdown.daysRemaining, 7)
        XCTAssertFalse(countdown.isRaceDay)
        XCTAssertEqual(countdown.dDayText, "D-7")
        XCTAssertEqual(countdown.goalText, "1:30:00")
        XCTAssertEqual(countdown.target.eventName, "HYROX Seoul")
    }

    func testRaceDayShowsDDayLabel() throws {
        let persistence = try PersistenceController(inMemory: true)
        // 대회 당일 이른 아침 — 시각이 "지금" 보다 앞서도 당일로 센다.
        try persistence.upsertRaceTarget(
            RaceTarget(eventName: "HYROX Busan", date: date(offsetDays: 0), division: .menOpenSingle)
        )

        let vm = makeViewModel(persistence)
        vm.load()

        let countdown = try XCTUnwrap(vm.raceCountdown)
        XCTAssertEqual(countdown.daysRemaining, 0)
        XCTAssertTrue(countdown.isRaceDay)
        XCTAssertEqual(countdown.dDayText, HyroxSimStrings.Localizable.Home.RaceTarget.dday)
        XCTAssertNil(countdown.goalText)
    }

    func testPastRaceIsExcludedFromCountdown() throws {
        let persistence = try PersistenceController(inMemory: true)
        try persistence.upsertRaceTarget(
            RaceTarget(eventName: "HYROX Tokyo", date: date(offsetDays: -1), division: .menProSingle)
        )

        let vm = makeViewModel(persistence)
        vm.load()

        XCTAssertNil(vm.raceCountdown)
        // 지난 대회라도 디비전 정보는 남아 훈련 세션 무게 기준으로 쓰인다.
        XCTAssertEqual(vm.trainingDivision, .menProSingle)
    }

    func testNearestUpcomingRaceWins() throws {
        let persistence = try PersistenceController(inMemory: true)
        try persistence.upsertRaceTarget(RaceTarget(eventName: "Later", date: date(offsetDays: 60)))
        try persistence.upsertRaceTarget(RaceTarget(eventName: "Sooner", date: date(offsetDays: 3)))

        let vm = makeViewModel(persistence)
        vm.load()

        XCTAssertEqual(vm.raceCountdown?.target.eventName, "Sooner")
        XCTAssertEqual(vm.raceCountdown?.dDayText, "D-3")
    }
}

// MARK: - 훈련 세션 · 목표 override

@MainActor
final class HomeViewModelTrainingSessionTests: XCTestCase {

    private func makeViewModel(
        _ persistence: PersistenceController,
        goalOverrideStore: TemplateGoalOverrideStore? = nil
    ) -> HomeViewModel {
        HomeViewModel(
            persistence: persistence,
            goalOverrideStore: goalOverrideStore
                ?? TemplateGoalOverrideStore(
                    defaults: UserDefaults(suiteName: "com.hyroxsim.tests.home.\(UUID().uuidString)") ?? .standard
                )
        )
    }

    func testTrainingSessionsExposeEveryKind() throws {
        let vm = makeViewModel(try PersistenceController(inMemory: true))
        vm.load()

        XCTAssertEqual(vm.trainingSessions.count, TrainingSessionKind.allCases.count)
        XCTAssertEqual(vm.trainingSessions.map(\.kind), TrainingSessionKind.allCases)
        // 프리셋 캐러셀과 섞이면 안 된다.
        XCTAssertEqual(vm.presets.count, 9)
        XCTAssertTrue(vm.trainingSessions.allSatisfy { session in
            !vm.presets.contains { $0.id == session.id }
        })
    }

    func testTrainingSessionNamesUseLocalizedStrings() throws {
        let vm = makeViewModel(try PersistenceController(inMemory: true))
        vm.load()

        for item in vm.trainingSessions {
            XCTAssertEqual(item.template.name, TrainingSessionLocalization.name(for: item.kind))
            XCTAssertFalse(item.template.name.isEmpty)
        }
    }

    /// 세션 이름/설명 키가 실제로 앱 번들의 `Localizable.strings` 에 있어야 한다.
    /// 없으면 코어의 영문 기본값으로 조용히 떨어지므로, 누락을 여기서 잡는다.
    func testTrainingSessionLocalizationKeysExistInBundle() {
        let bundle = Bundle(for: HomeViewModel.self)
        let sentinel = "__missing__"

        for kind in TrainingSessionKind.allCases {
            for key in [kind.nameLocalizationKey, kind.summaryLocalizationKey] {
                let value = bundle.localizedString(forKey: key, value: sentinel, table: "Localizable")
                XCTAssertNotEqual(value, sentinel, "missing localized string for \(key)")
                XCTAssertFalse(value.isEmpty, "empty localized string for \(key)")
            }
        }
    }

    func testTrainingSessionWeightsFollowRaceDivision() throws {
        let persistence = try PersistenceController(inMemory: true)
        try persistence.upsertRaceTarget(
            RaceTarget(
                eventName: "HYROX Seoul",
                date: Date().addingTimeInterval(14 * 86_400),
                division: .womenOpenSingle
            )
        )

        let vm = makeViewModel(persistence)
        vm.load()

        XCTAssertEqual(vm.trainingDivision, .womenOpenSingle)
        let ladder = try XCTUnwrap(vm.trainingSessions.first { $0.kind == .wallBallLadder })
        XCTAssertTrue(ladder.template.segments.allSatisfy { $0.weightKg == 4 })
    }

    func testDefaultTrainingDivisionWithoutAnyRace() throws {
        let vm = makeViewModel(try PersistenceController(inMemory: true))
        vm.load()
        XCTAssertEqual(vm.trainingDivision, HomeViewModel.fallbackTrainingDivision)
    }

    /// 홈 프리셋 카드가 사용자 목표를 반영하지 않던 문제 회귀 테스트.
    func testPresetsApplySavedGoalOverrides() throws {
        let suiteName = "com.hyroxsim.tests.home.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TemplateGoalOverrideStore(defaults: defaults)
        var customised = HyroxPresets.template(for: .menProSingle)
        customised.segments = customised.segments.map { segment in
            var copy = segment
            copy.goalDurationSeconds = 60
            return copy
        }
        store.save(customised)

        let vm = makeViewModel(try PersistenceController(inMemory: true), goalOverrideStore: store)
        vm.load()

        let preset = try XCTUnwrap(vm.presets.first { $0.division == .menProSingle })
        XCTAssertEqual(preset.estimatedDurationSeconds, 60 * Double(preset.segments.count))
        XCTAssertNotEqual(
            preset.estimatedDurationSeconds,
            HyroxPresets.template(for: .menProSingle).estimatedDurationSeconds
        )
    }

    /// 목표가 바뀌면 홈이 다시 그려지도록 알림을 구독한다.
    func testGoalOverrideNotificationTriggersReload() throws {
        let suiteName = "com.hyroxsim.tests.home.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = TemplateGoalOverrideStore(defaults: defaults)
        let vm = makeViewModel(try PersistenceController(inMemory: true), goalOverrideStore: store)
        vm.load()

        let reloaded = expectation(description: "home reloaded")
        vm.onDataChanged = { reloaded.fulfill() }

        store.save(HyroxPresets.template(for: .menOpenSingle))

        wait(for: [reloaded], timeout: 2)
    }
}
