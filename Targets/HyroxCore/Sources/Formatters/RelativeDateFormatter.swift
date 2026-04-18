//
//  RelativeDateFormatter.swift
//  HyroxCore
//
//  Created by bbdyno on 4/18/26.
//

import Foundation

public enum RelativeDateFormatter {

    /// Returns a relative date string like "5 min. ago", "yesterday", "Mar 5".
    /// 앱의 Bundle preferred localization 을 기준으로 매 호출마다 포매터를 새로 구성.
    /// (캐시를 두지 않는 이유: Swift 6 엄격 동시성에서 static 가변 캐시가 데이터 레이스 원인이 됨.
    /// RelativeDateTimeFormatter 생성 비용은 UI 렌더 비용 대비 무시 가능.)
    public static func short(_ date: Date) -> String {
        let localeIdentifier = Bundle.main.preferredLocalizations.first ?? "en"
        let formatter = Foundation.RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: localeIdentifier)
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
