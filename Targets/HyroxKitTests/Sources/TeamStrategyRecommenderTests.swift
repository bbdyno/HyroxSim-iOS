//
//  TeamStrategyRecommenderTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class TeamStrategyRecommenderTests: XCTestCase {

    private func reference(for entry: TeamEntry, goal: Int = 4_500) throws -> TeamSplitReference {
        let dataset = try PaceReferenceLoader.loadBundledPaceData().dataset(for: entry.referenceDivision)
        return TeamSplitReference.make(entry: entry, dataset: dataset, goalSeconds: goal)
    }

    private func index(_ kind: StationKind) -> Int { StationKind.standardOrder.firstIndex(of: kind)! }

    private func preferences(_ pairs: [StationKind: Int]) -> [Int?] {
        StationKind.standardOrder.map { pairs[$0] }
    }

    private func assertRowsSumToOne(_ strategy: TeamStrategy, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(strategy.stationShares.count, 8, file: file, line: line)
        for row in strategy.stationShares {
            XCTAssertEqual(row.reduce(0, +), 1, accuracy: 1e-9, file: file, line: line)
        }
        XCTAssertEqual(strategy.memberLoadShares.reduce(0, +), 1, accuracy: 1e-9, file: file, line: line)
    }

    // MARK: - 더블스

    func testDoublesWithNoInputIsEven() throws {
        let entry = TeamEntry.doubles(.menOpenDouble)
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry, strongerSlot: [], reference: try reference(for: entry)
        )
        assertRowsSumToOne(strategy)
        for row in strategy.stationShares {
            XCTAssertEqual(row[0], 0.5, accuracy: 1e-9)
        }
        XCTAssertTrue(strategy.unhonoredStationIndices.isEmpty)
    }

    func testDoublesGivesTheStrongerPartnerTheLargerShare() throws {
        let entry = TeamEntry.doubles(.mixedDouble)
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry,
            strongerSlot: preferences([.sledPush: 1, .wallBalls: 0]),
            reference: try reference(for: entry)
        )
        assertRowsSumToOne(strategy)
        XCTAssertEqual(strategy.stationShares[index(.sledPush)][1], TeamStrategyRecommender.favoredShare, accuracy: 1e-9)
        XCTAssertEqual(strategy.stationShares[index(.wallBalls)][0], TeamStrategyRecommender.favoredShare, accuracy: 1e-9)
    }

    /// 한 사람이 여러 곳에서 강해도 일이 몰리지 않게, 강점 입력이 없던 스테이션에서 덜어 준다.
    func testDoublesRebalancesUsingOnlyUnratedStations() throws {
        let entry = TeamEntry.doubles(.menOpenDouble)
        let rated: [StationKind: Int] = [.skiErg: 0, .sledPull: 0, .burpeeBroadJumps: 0, .rowing: 0, .wallBalls: 0]
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry, strongerSlot: preferences(rated), reference: try reference(for: entry)
        )
        assertRowsSumToOne(strategy)

        // 강점이 지정된 스테이션은 그대로.
        for kind in rated.keys {
            XCTAssertEqual(strategy.stationShares[index(kind)][0], TeamStrategyRecommender.favoredShare, accuracy: 1e-9, "\(kind)")
        }
        // 지정 안 된 스테이션 중 적어도 하나는 B 쪽으로 넘어갔다.
        let unrated: [StationKind] = [.sledPush, .farmersCarry, .sandbagLunges]
        XCTAssertTrue(unrated.contains { strategy.stationShares[index($0)][0] < 0.5 - 1e-9 })
        // 어느 스테이션도 65:35 를 넘지 않는다.
        for row in strategy.stationShares {
            XCTAssertLessThanOrEqual(row.max()!, TeamStrategyRecommender.favoredShare + 1e-9)
        }
        // 균형을 맞추기 전(5곳 × 65%)보다 A 의 부하가 줄었다.
        let reference = try reference(for: entry)
        let naive = StationKind.standardOrder.reduce(0.0) { sum, kind in
            sum + reference.seconds(for: kind) * (rated[kind] == 0 ? 0.65 : 0.5)
        } / reference.stationTotalSeconds
        XCTAssertLessThan(strategy.memberLoadShares[0], naive)
    }

    func testDoublesStaysWithinLoadLimitWhenItCan() throws {
        let entry = TeamEntry.doubles(.womenOpenDouble)
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry,
            strongerSlot: preferences([.skiErg: 0, .rowing: 0, .wallBalls: 0]),
            reference: try reference(for: entry)
        )
        XCTAssertLessThanOrEqual(strategy.memberLoadShares.max()!, TeamStrategyRecommender.maxLoadShare + 1e-9)
    }

    func testOutOfRangeInputIsTreatedAsNoPreference() throws {
        let entry = TeamEntry.doubles(.menOpenDouble)
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry, strongerSlot: [7, -1, 2], reference: try reference(for: entry)
        )
        for row in strategy.stationShares { XCTAssertEqual(row[0], 0.5, accuracy: 1e-9) }
    }

    // MARK: - 릴레이

    private func owners(_ strategy: TeamStrategy) -> [Int] {
        strategy.stationShares.map { $0.firstIndex { $0 >= 0.999 }! }
    }

    func testRelayWithNoInputKeepsTheDefaultRotation() throws {
        let entry = TeamEntry.relay(.men)
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry, strongerSlot: [], reference: try reference(for: entry)
        )
        assertRowsSumToOne(strategy)
        let assigned = owners(strategy)
        for slot in 0..<4 { XCTAssertEqual(assigned.filter { $0 == slot }.count, 2, "two legs each") }
    }

    func testRelayHonoursPreferencesWithTwoLegsEach() throws {
        let entry = TeamEntry.relay(.mixed)
        let wanted: [StationKind: Int] = [.sledPush: 3, .sledPull: 3, .wallBalls: 0, .skiErg: 1]
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry, strongerSlot: preferences(wanted), reference: try reference(for: entry)
        )
        assertRowsSumToOne(strategy)
        let assigned = owners(strategy)
        for (kind, slot) in wanted { XCTAssertEqual(assigned[index(kind)], slot, "\(kind)") }
        for slot in 0..<4 { XCTAssertEqual(assigned.filter { $0 == slot }.count, 2) }
        XCTAssertTrue(strategy.unhonoredStationIndices.isEmpty)
    }

    /// 한 사람을 세 군데에 지목하면 두 군데만 들어줄 수 있다 — 못 들어준 곳을 알려 준다.
    func testRelayReportsPreferencesItCouldNotHonour() throws {
        let entry = TeamEntry.relay(.women)
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry,
            strongerSlot: preferences([.sledPush: 2, .sledPull: 2, .farmersCarry: 2]),
            reference: try reference(for: entry)
        )
        let assigned = owners(strategy)
        XCTAssertEqual(assigned.filter { $0 == 2 }.count, 2)
        XCTAssertEqual(strategy.unhonoredStationIndices.count, 1)
        let missed = strategy.unhonoredStationIndices[0]
        XCTAssertTrue([index(.sledPush), index(.sledPull), index(.farmersCarry)].contains(missed))
        XCTAssertNotEqual(assigned[missed], 2)
    }

    // MARK: - 계획에 적용

    func testRecommendationAppliesToAPlan() throws {
        let entry = TeamEntry.doubles(.menOpenDouble)
        let reference = try reference(for: entry)
        let strategy = TeamStrategyRecommender.recommend(
            entry: entry, strongerSlot: preferences([.rowing: 1]), reference: reference
        )
        let plan = TeamSplitPlan.balanced(entry: entry, goalTotalSeconds: 4_500)
            .settingStationShares(strategy.stationShares)

        XCTAssertEqual(plan.share(stationAt: index(.rowing), slot: 1), 0.65, accuracy: 1e-9)
        XCTAssertFalse(plan.isBalanced)
        let result = TeamSplitCalculator.result(for: plan, reference: reference)
        XCTAssertEqual(result.members.count, 2)
    }
}
