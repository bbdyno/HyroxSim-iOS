//
//  LegacyPurchaseRule.swift
//  HyroxCore
//
//  Created by bbdyno on 10/12/26.
//

import Foundation

/// 유료 앱 시절(2.0 이전) 구매자인지 가린다.
///
/// App Store 는 사용자가 앱을 처음 받았을 때의 빌드 번호(`CFBundleVersion`)를
/// `AppTransaction.originalAppVersion` 으로 알려 준다. 이 앱의 빌드 번호는
/// `YYYY.MM.DD.N` 이라, 무료 전환 첫 빌드보다 앞이면 돈을 내고 받은 사용자다.
public enum LegacyPurchaseRule {

    /// 무료로 전환된 첫 빌드. 마지막 유료 빌드(`2026.10.07.1`, 1.5.0)보다 뒤이고,
    /// 스토어에 처음 올라가는 2.0 빌드보다 뒤가 아니어야 한다.
    public static let firstFreeBuild = "2026.10.12.1"

    public static func isLegacyBuyer(originalBuild: String) -> Bool {
        isLegacyBuyer(originalBuild: originalBuild, firstFreeBuild: firstFreeBuild)
    }

    public static func isLegacyBuyer(originalBuild: String, firstFreeBuild: String) -> Bool {
        guard let original = components(originalBuild), let cutoff = components(firstFreeBuild) else {
            // 해석할 수 없는 값으로 유료 구매자를 잠그느니 열어 주는 쪽이 낫다.
            return !originalBuild.trimmingCharacters(in: .whitespaces).isEmpty
        }
        for i in 0..<max(original.count, cutoff.count) {
            let a = i < original.count ? original[i] : 0
            let b = i < cutoff.count ? cutoff[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    private static func components(_ build: String) -> [Int]? {
        let parts = build.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
