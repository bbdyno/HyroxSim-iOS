//
//  SubscriptionStoreTests.swift
//  HyroxSimTests
//
//  Created by bbdyno on 10/12/26.
//

import XCTest
import StoreKit
import StoreKitTest
import HyroxCore
@testable import HyroxSim

/// 스토어 응답을 마음대로 정하는 가짜.
private final class FakeStore: @unchecked Sendable {
    private let lock = NSLock()
    private var _subscribed = false
    private var _originalBuild: String?
    private var _syncCount = 0
    private var continuation: AsyncStream<Void>.Continuation?

    var subscribed: Bool {
        get { lock.withLock { _subscribed } }
        set { lock.withLock { _subscribed = newValue } }
    }
    var originalBuild: String? {
        get { lock.withLock { _originalBuild } }
        set { lock.withLock { _originalBuild = newValue } }
    }
    var syncCount: Int { lock.withLock { _syncCount } }

    func emitUpdate() { lock.withLock { continuation }?.yield() }

    var backend: SubscriptionBackend {
        SubscriptionBackend(
            hasActiveSubscription: { [self] _ in subscribed },
            originalProductionBuild: { [self] in originalBuild },
            transactionUpdates: { [self] in
                AsyncStream { cont in lock.withLock { continuation = cont } }
            },
            sync: { [self] in lock.withLock { _syncCount += 1 } }
        )
    }
}

@MainActor
final class SubscriptionStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var fake: FakeStore!

    override func setUp() async throws {
        suiteName = "SubscriptionStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fake = FakeStore()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> SubscriptionStore {
        SubscriptionStore(defaults: defaults, backend: fake.backend)
    }

    // MARK: - 구독

    func testStartsFree() async {
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.tier, .free)
        XCTAssertFalse(store.gate.allows(.levelAssessment))
    }

    func testActiveSubscriptionUnlocksAndNotifies() async {
        let store = makeStore()
        let changed = expectation(forNotification: SubscriptionStore.didChangeNotification, object: store)
        fake.subscribed = true

        await store.refresh()

        XCTAssertEqual(store.tier, .subscriber)
        XCTAssertTrue(store.gate.allows(.levelAssessment))
        await fulfillment(of: [changed], timeout: 2)
    }

    /// 구독 상태는 다음 실행에서 스토어 응답을 기다리지 않고 바로 보여야 한다.
    func testTierIsCachedForNextLaunch() async {
        fake.subscribed = true
        await makeStore().refresh()

        XCTAssertEqual(makeStore().tier, .subscriber)
    }

    func testExpiredSubscriptionFallsBackToFree() async {
        let store = makeStore()
        fake.subscribed = true
        await store.refresh()
        XCTAssertEqual(store.tier, .subscriber)

        fake.subscribed = false
        await store.refresh()

        XCTAssertEqual(store.tier, .free)
        XCTAssertEqual(makeStore().tier, .free)
    }

    /// 갱신·환불처럼 앱 밖에서 생긴 변화도 반영한다.
    func testTransactionUpdateTriggersRefresh() async throws {
        let store = makeStore()
        store.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.tier, .free)

        let changed = expectation(forNotification: SubscriptionStore.didChangeNotification, object: store)
        fake.subscribed = true
        fake.emitUpdate()

        await fulfillment(of: [changed], timeout: 3)
        XCTAssertEqual(store.tier, .subscriber)
    }

    func testRestoreSyncsThenRefreshes() async {
        let store = makeStore()
        fake.subscribed = true

        await store.restore()

        XCTAssertEqual(fake.syncCount, 1)
        XCTAssertEqual(store.tier, .subscriber)
    }

    // MARK: - 유료 앱 구매자

    /// App Store 가 알려 준 최초 설치 빌드가 유료 시절이면 구독 없이 전부 열린다.
    func testPaidBuildFromAppStoreIsLegacyBuyer() async {
        fake.originalBuild = "2026.09.20.1"
        let store = makeStore()

        await store.refresh()

        XCTAssertEqual(store.tier, .legacyBuyer)
        XCTAssertTrue(store.gate.canOpenHistory(at: 100))
    }

    func testFreeEraBuildIsNotLegacy() async {
        fake.originalBuild = LegacyPurchaseRule.firstFreeBuild
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.tier, .free)
    }

    /// 한 번 구매자로 확인되면, 이후 스토어가 응답하지 않아도 그대로다.
    func testLegacyBuyerIsRememberedWhenStoreLaterFails() async {
        fake.originalBuild = "2026.04.18.3"
        await makeStore().refresh()

        fake.originalBuild = nil
        let relaunched = makeStore()
        XCTAssertEqual(relaunched.tier, .legacyBuyer)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.tier, .legacyBuyer)
    }

    /// 2.0 첫 실행 때 기록 저장소가 이미 있으면 유료 버전에서 올라온 사용자다.
    /// 오프라인이라 스토어가 답하지 못해도 잠기지 않는다.
    func testUpgradeFromPaidVersionIsUnlockedWithoutStore() async {
        SubscriptionStore.recordInstallOrigin(defaults: defaults, storeExists: true)
        let store = makeStore()
        XCTAssertEqual(store.tier, .legacyBuyer)
        await store.refresh()
        XCTAssertEqual(store.tier, .legacyBuyer)
    }

    func testFreshInstallIsNotLegacy_andOriginIsOnlyRecordedOnce() {
        SubscriptionStore.recordInstallOrigin(defaults: defaults, storeExists: false)
        XCTAssertEqual(makeStore().tier, .free)

        // 무료로 쓰다가 기록이 쌓인 뒤의 실행. 구매자로 바뀌면 안 된다.
        SubscriptionStore.recordInstallOrigin(defaults: defaults, storeExists: true)
        XCTAssertEqual(makeStore().tier, .free)
    }

    /// 구매자가 구독까지 했더라도 등급은 구매자다 (구독이 끝나도 잠기지 않는다).
    func testLegacyBuyerOutranksSubscription() async {
        fake.originalBuild = "2026.10.07.1"
        fake.subscribed = true
        let store = makeStore()
        await store.refresh()
        XCTAssertEqual(store.tier, .legacyBuyer)
    }

    func testForcedTierIgnoresStore() async {
        fake.subscribed = false
        let store = SubscriptionStore(defaults: defaults, forcedTier: .subscriber, backend: fake.backend)
        await store.refresh()
        XCTAssertEqual(store.tier, .subscriber)
    }

    // MARK: - 실제 StoreKit (로컬 상품 정의)

    /// `HyroxSim.storekit` 의 상품으로 실제 구매 흐름을 돈다. 로컬 StoreKit 테스트 서버가
    /// 붙지 않는 환경에서는 건너뛴다 (상품이 조회되지 않는다).
    func testRealPurchaseFlowWithLocalProducts() async throws {
        let session = try SKTestSession(configurationFileNamed: "HyroxSim")
        session.disableDialogs = true
        session.clearTransactions()
        defer { session.clearTransactions() }

        let store = SubscriptionStore(defaults: defaults)
        await store.loadProducts()
        try XCTSkipIf(store.products.isEmpty, "local StoreKit test server unavailable in this environment")

        XCTAssertEqual(store.products.first?.id, SubscriptionStore.yearlyProductID, "yearly is listed first")
        XCTAssertEqual(store.yearlyProduct?.price, 29000)
        XCTAssertEqual(store.monthlyProduct?.price, 4900)

        let unlocked = try await store.purchase(try XCTUnwrap(store.monthlyProduct))
        XCTAssertTrue(unlocked)
        XCTAssertEqual(store.tier, .subscriber)

        try session.expireSubscription(productIdentifier: SubscriptionStore.monthlyProductID)
        await store.refresh()
        XCTAssertEqual(store.tier, .free)
    }
}
