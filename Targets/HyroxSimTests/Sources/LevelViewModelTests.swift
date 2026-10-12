//
//  LevelViewModelTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import HyroxCore
@testable import HyroxSim

final class LevelViewModelTests: XCTestCase {

    private func makeViewModel(ageGroup: String? = nil) throws -> LevelViewModel {
        let dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: .menOpenSingle)
        return LevelViewModel(workout: ScreenshotFixtures.fullRaceWorkout, dataset: dataset, ageGroup: ageGroup)
    }

    func testPercentTextFormatting() {
        XCTAssertEqual(LevelViewModel.percentText(18.4, clamped: false), "18%")
        XCTAssertEqual(LevelViewModel.percentText(18.5, clamped: false), "19%")
        XCTAssertEqual(LevelViewModel.percentText(0.6, clamped: false), "0.6%")
        XCTAssertEqual(LevelViewModel.percentText(1.0, clamped: false), "1%")
        XCTAssertEqual(LevelViewModel.percentText(0.1, clamped: true), "<0.1%")
        XCTAssertEqual(LevelViewModel.percentText(99.9, clamped: true), ">99.9%")
    }

    func testFullRaceProducesStandingAndNineSegmentRows() throws {
        let vm = try makeViewModel()

        XCTAssertTrue(ScreenshotFixtures.fullRaceWorkout.isStandardHyroxCourse)
        XCTAssertTrue(vm.caption.contains("1:27:57"))
        XCTAssertEqual(vm.headlineValue, "51%")
        XCTAssertEqual(vm.rows.count, 9)
        XCTAssertEqual(vm.markerPosition, 0.51, accuracy: 0.01)
        XCTAssertNotNil(vm.populationText)
        XCTAssertNotNil(vm.milestoneTitle)

        // 손실이 큰 순으로, 느린 구간 → 빠른 구간.
        XCTAssertEqual(vm.rows.first?.tone, .lost)
        XCTAssertEqual(vm.rows.last?.tone, .gained)
        XCTAssertTrue(vm.rows.first?.delta.hasPrefix("+") ?? false)
        XCTAssertTrue(vm.rows.last?.delta.hasPrefix("−") ?? false)
        XCTAssertNotNil(vm.recoverableText)
    }

    /// 월볼·썰매가 약점인 기록이므로 근력 보강(FitBoost)을 권한다.
    func testStrengthSuggestionFollowsWeakStations() throws {
        XCTAssertTrue(try makeViewModel().suggestsStrengthWork)
    }

    func testAgeGroupSelectionAddsAndRemovesStanding() throws {
        var vm = try makeViewModel()
        XCTAssertNil(vm.assessment?.ageGroup)
        XCTAssertEqual(vm.ageGroupValue, "—")

        vm.selectAgeGroup("30-34")
        XCTAssertEqual(vm.assessment?.ageGroup?.label, "30-34")
        XCTAssertNotEqual(vm.ageGroupValue, "—")

        vm.selectAgeGroup(nil)
        XCTAssertNil(vm.assessment?.ageGroup)
    }

    /// 저장된 연령대가 이 디비전 데이터에 없으면 무시한다.
    func testUnknownStoredAgeGroupIsIgnored() throws {
        let vm = try makeViewModel(ageGroup: "not-a-group")
        XCTAssertNil(vm.ageGroup)
        XCTAssertNil(vm.assessment?.ageGroup)
    }
}
