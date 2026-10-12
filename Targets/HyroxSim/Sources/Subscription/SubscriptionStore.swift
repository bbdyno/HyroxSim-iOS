//
//  SubscriptionStore.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import Foundation
import HyroxCore
import os
import StoreKit

/// `SubscriptionStore` 가 App Store 에 묻는 것들. 테스트에서는 가짜로 바꿔 끼운다.
struct SubscriptionBackend: Sendable {
    /// 지금 유효한 구독이 있는가.
    var hasActiveSubscription: @Sendable (_ productIDs: Set<String>) async -> Bool
    /// 앱을 처음 받았을 때의 빌드 번호. 실제 스토어(production)에서 받은 경우에만 값이 있다.
    var originalProductionBuild: @Sendable () async -> String?
    /// 구독 갱신·환불·다른 기기 구매처럼 앱 밖에서 생긴 변화.
    var transactionUpdates: @Sendable () -> AsyncStream<Void>
    /// 구매 복원.
    var sync: @Sendable () async -> Void

    static let appStore = SubscriptionBackend(
        hasActiveSubscription: { productIDs in
            for await entitlement in Transaction.currentEntitlements {
                guard case .verified(let transaction) = entitlement else { continue }
                if productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                    return true
                }
            }
            return false
        },
        originalProductionBuild: {
            guard let result = try? await AppTransaction.shared, case .verified(let app) = result else {
                return nil
            }
            // 샌드박스·TestFlight 는 최초 버전을 항상 "1.0" 으로 준다. 그대로 믿으면
            // 테스트 계정이 전부 구매자가 되어 페이월을 확인할 수 없다.
            guard app.environment == .production else { return nil }
            return app.originalAppVersion
        },
        transactionUpdates: {
            AsyncStream { continuation in
                let task = Task {
                    for await update in Transaction.updates {
                        if case .verified(let transaction) = update {
                            await transaction.finish()
                        }
                        continuation.yield()
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        },
        sync: { try? await AppStore.sync() }
    )
}

/// 구독 상태의 단일 출처. 화면은 `gate` 에 묻고, 바뀌면 `didChangeNotification` 을 받는다.
///
/// 등급은 세 가지 근거로 정한다.
/// 1. 유효한 자동 갱신 구독 (`Transaction.currentEntitlements`)
/// 2. 유료 앱 시절 구매 — App Store 가 알려 주는 최초 설치 빌드 (`AppTransaction`)
/// 3. 유료 앱에서 업데이트한 흔적 — 2.0 첫 실행 때 이미 기록 저장소가 있었음
///
/// 3번은 오프라인이거나 App Store 응답이 실패해도 기존 구매자가 잠기지 않게 하는 안전망이다.
/// 구매자 판정은 한 번 참이 되면 기기에 남겨 다시 묻지 않는다.
@MainActor
final class SubscriptionStore {

    static let monthlyProductID = "com.bbdyno.app.HyroxSim.pro.monthly"
    static let yearlyProductID = "com.bbdyno.app.HyroxSim.pro.yearly"
    static let productIDs: Set<String> = [monthlyProductID, yearlyProductID]

    static let didChangeNotification = Notification.Name("SubscriptionStore.didChange")

    private enum Key {
        static let cachedTier = "subscription.cachedTier"
        static let legacyBuyer = "subscription.isLegacyBuyer"
        static let originChecked = "subscription.originChecked"
    }

    private let logger = Logger(subsystem: "com.bbdyno.app.HyroxSim", category: "Subscription")
    private let defaults: UserDefaults
    private let forcedTier: AccessTier?
    private let backend: SubscriptionBackend
    private var updatesTask: Task<Void, Never>?

    private(set) var tier: AccessTier
    private(set) var products: [Product] = []

    var gate: FeatureGate { FeatureGate(tier: tier) }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyProductID } }
    var yearlyProduct: Product? { products.first { $0.id == Self.yearlyProductID } }

    /// - Parameter forcedTier: 스크린샷·UI 테스트처럼 스토어 없이 등급을 고정할 때.
    init(
        defaults: UserDefaults = .standard,
        forcedTier: AccessTier? = nil,
        backend: SubscriptionBackend = .appStore
    ) {
        self.defaults = defaults
        self.backend = backend
        self.forcedTier = forcedTier
        if let forcedTier {
            tier = forcedTier
        } else if defaults.bool(forKey: Key.legacyBuyer) {
            tier = .legacyBuyer
        } else {
            // 스토어 확인이 끝나기 전에도 지난번 상태로 바로 그린다. 구독자가 실행할 때마다
            // 잠긴 화면을 잠깐 보지 않게 한다.
            tier = defaults.string(forKey: Key.cachedTier).flatMap(AccessTier.init(rawValue:)) ?? .free
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// 2.0 을 처음 실행하는 순간에 한 번만 부른다. 기록 저장소를 열기 **전에** 불러야 한다 —
    /// 저장소가 이미 있다면 유료 버전에서 올라온 사용자다.
    static func recordInstallOrigin(
        defaults: UserDefaults = .standard,
        storeExists: Bool
    ) {
        guard !defaults.bool(forKey: Key.originChecked) else { return }
        defaults.set(true, forKey: Key.originChecked)
        if storeExists {
            defaults.set(true, forKey: Key.legacyBuyer)
        }
    }

    /// SwiftData 기본 저장소가 이미 디스크에 있는지.
    static func defaultStoreExists(fileManager: FileManager = .default) -> Bool {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return false
        }
        return fileManager.fileExists(atPath: support.appendingPathComponent("default.store").path)
    }

    func start() {
        guard forcedTier == nil, updatesTask == nil else { return }
        updatesTask = Task { [weak self, backend] in
            for await _ in backend.transactionUpdates() {
                await self?.refresh()
            }
        }
        Task { [weak self] in
            await self?.refresh()
            await self?.loadProducts()
        }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // 연 구독을 앞에.
            products = loaded.sorted { $0.price > $1.price }
        } catch {
            logger.error("상품 조회 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refresh() async {
        guard forcedTier == nil else { return }
        let isSubscribed = await backend.hasActiveSubscription(Self.productIDs)
        let isLegacy = await resolveLegacyBuyer()
        apply(isLegacy ? .legacyBuyer : (isSubscribed ? .subscriber : .free))
    }

    /// - Returns: 구매가 완료되어 등급이 올라갔으면 `true`. 취소·승인 대기는 `false`.
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            await transaction.finish()
            await refresh()
            return tier.isUnlocked
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        await backend.sync()
        await refresh()
    }

    // MARK: - Private

    private func resolveLegacyBuyer() async -> Bool {
        if defaults.bool(forKey: Key.legacyBuyer) { return true }
        guard let build = await backend.originalProductionBuild(),
              LegacyPurchaseRule.isLegacyBuyer(originalBuild: build) else { return false }
        defaults.set(true, forKey: Key.legacyBuyer)
        return true
    }

    private func apply(_ newTier: AccessTier) {
        defaults.set(newTier.rawValue, forKey: Key.cachedTier)
        guard newTier != tier else { return }
        tier = newTier
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
