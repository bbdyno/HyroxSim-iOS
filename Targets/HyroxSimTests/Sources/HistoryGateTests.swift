//
//  HistoryGateTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import HyroxCore
import HyroxPersistenceApple
@testable import HyroxSim

private final class HistoryDelegateSpy: HistoryViewControllerDelegate {
    var selected: [CompletedWorkout] = []
    var lockedTaps = 0
    func historyDidSelect(_ workout: CompletedWorkout) { selected.append(workout) }
    func historyDidTapLockedRows() { lockedTaps += 1 }
}

/// 무료 사용자는 최근 5개만 열 수 있고, 나머지는 잠긴 행 하나로 묶인다.
/// 기록 자체는 지워지지 않는다 — 구독하면 전부 다시 보인다.
@MainActor
final class HistoryGateTests: XCTestCase {

    private func makeHistory(
        count: Int, tier: AccessTier
    ) throws -> (HistoryViewController, UITableView, HistoryDelegateSpy, PersistenceController) {
        let persistence = try PersistenceController(inMemory: true)
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        for i in 0..<count {
            let start = base.addingTimeInterval(Double(i) * 86_400)
            try persistence.saveCompletedWorkout(CompletedWorkout(
                templateName: "W\(i)",
                division: .menOpenSingle,
                startedAt: start,
                finishedAt: start.addingTimeInterval(3_600),
                segments: []
            ))
        }
        let vc = HistoryViewController(viewModel: HistoryViewModel(persistence: persistence))
        vc.gateProvider = { FeatureGate(tier: tier) }
        let spy = HistoryDelegateSpy()
        vc.delegate = spy
        vc.loadViewIfNeeded()
        vc.viewWillAppear(false)
        let table = try XCTUnwrap(vc.view.subviews.compactMap { $0 as? UITableView }.first)
        return (vc, table, spy, persistence)
    }

    func testFreeTierShowsFiveNewestPlusOneLockedRow() throws {
        let (vc, table, spy, persistence) = try makeHistory(count: 8, tier: .free)

        XCTAssertEqual(vc.tableView(table, numberOfRowsInSection: 0), 6)

        // 최신 기록은 열린다.
        vc.tableView(table, didSelectRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(spy.selected.map(\.templateName), ["W7"])
        vc.tableView(table, didSelectRowAt: IndexPath(row: 4, section: 0))
        XCTAssertEqual(spy.selected.map(\.templateName), ["W7", "W3"])

        // 여섯 번째 줄은 잠긴 행 — 기록을 열지 않고 페이월을 요청한다.
        vc.tableView(table, didSelectRowAt: IndexPath(row: 5, section: 0))
        XCTAssertEqual(spy.lockedTaps, 1)
        XCTAssertEqual(spy.selected.count, 2)
        XCTAssertNil(vc.tableView(table, trailingSwipeActionsConfigurationForRowAt: IndexPath(row: 5, section: 0)))

        // 잠겨 있어도 기록은 그대로 저장되어 있다.
        XCTAssertEqual(try persistence.fetchAllCompletedWorkouts().count, 8)
    }

    func testFreeTierWithFewWorkoutsHasNoLockedRow() throws {
        let (vc, table, _, _) = try makeHistory(count: 5, tier: .free)
        XCTAssertEqual(vc.tableView(table, numberOfRowsInSection: 0), 5)
    }

    func testUnlockedTiersShowEverything() throws {
        for tier in [AccessTier.subscriber, .legacyBuyer] {
            let (vc, table, spy, _) = try makeHistory(count: 8, tier: tier)
            XCTAssertEqual(vc.tableView(table, numberOfRowsInSection: 0), 8)
            vc.tableView(table, didSelectRowAt: IndexPath(row: 7, section: 0))
            XCTAssertEqual(spy.selected.map(\.templateName), ["W0"])
            XCTAssertEqual(spy.lockedTaps, 0)
        }
    }
}
