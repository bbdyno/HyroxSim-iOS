//
//  FeatureGateTests.swift
//  HyroxKitTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
@testable import HyroxCore

final class FeatureGateTests: XCTestCase {

    func testFreeTierIsLimitedToTheAdvertisedCounts() {
        let gate = FeatureGate(tier: .free)

        XCTAssertTrue(gate.canOpenHistory(at: 4))
        XCTAssertFalse(gate.canOpenHistory(at: 5))
        XCTAssertEqual(gate.visibleHistoryCount(total: 12), 5)
        XCTAssertEqual(gate.visibleHistoryCount(total: 3), 3)

        XCTAssertTrue(gate.canCreateCustomTemplate(existingCount: 0))
        XCTAssertFalse(gate.canCreateCustomTemplate(existingCount: 1))

        XCTAssertTrue(gate.canStartTrainingSession(at: 0))
        XCTAssertFalse(gate.canStartTrainingSession(at: 1))

        XCTAssertTrue(gate.canAddRaceResult(existingCount: 0))
        XCTAssertFalse(gate.canAddRaceResult(existingCount: 1))

        XCTAssertTrue(gate.canUseShareTemplate(at: 0))
        XCTAssertFalse(gate.canUseShareTemplate(at: 1))

        for feature in PremiumFeature.allCases {
            XCTAssertFalse(gate.allows(feature), "\(feature) should be locked on the free tier")
        }
    }

    func testSubscribersAndLegacyBuyersHaveNoLimits() {
        for tier in [AccessTier.subscriber, .legacyBuyer] {
            let gate = FeatureGate(tier: tier)
            XCTAssertTrue(gate.canOpenHistory(at: 500))
            XCTAssertEqual(gate.visibleHistoryCount(total: 500), 500)
            XCTAssertTrue(gate.canCreateCustomTemplate(existingCount: 50))
            XCTAssertTrue(gate.canStartTrainingSession(at: 9))
            XCTAssertTrue(gate.canAddRaceResult(existingCount: 30))
            XCTAssertTrue(gate.canUseShareTemplate(at: 4))
            for feature in PremiumFeature.allCases {
                XCTAssertTrue(gate.allows(feature), "\(feature) should be open for \(tier)")
            }
        }
    }

    // MARK: - 유료 앱 구매자 판정

    /// 실제로 스토어에 나갔던 유료 빌드는 전부 구매자로 본다.
    func testEveryShippedPaidBuildCountsAsLegacy() {
        let shipped = [
            "2026.04.10.1", "2026.04.12.2", "2026.04.18.3",
            "2026.07.20.1", "2026.09.20.1", "2026.10.07.1"
        ]
        for build in shipped {
            XCTAssertTrue(LegacyPurchaseRule.isLegacyBuyer(originalBuild: build), build)
        }
    }

    func testFirstFreeBuildAndLaterAreNotLegacy() {
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: LegacyPurchaseRule.firstFreeBuild))
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "2026.10.12.2"))
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "2026.11.01.1"))
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "2027.01.01.1"))
    }

    /// 숫자로 비교해야 한다. 문자열 비교면 "2026.9.30.1" 이 "2026.10.12.1" 보다 뒤가 된다.
    func testComparisonIsNumericNotLexical() {
        XCTAssertTrue(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "2026.9.30.1"))
        XCTAssertTrue(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "2026.10.12"))
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "2026.10.12.1.0"))
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "2026.10.12.10"))
    }

    func testUnparseableBuildFavoursTheBuyer() {
        XCTAssertTrue(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "1.0-beta"))
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: ""))
        XCTAssertFalse(LegacyPurchaseRule.isLegacyBuyer(originalBuild: "  "))
    }
}
