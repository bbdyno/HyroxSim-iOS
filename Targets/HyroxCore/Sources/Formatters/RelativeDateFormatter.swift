//
//  RelativeDateFormatter.swift
//  HyroxCore
//
//  Created by bbdyno on 4/18/26.
//

import Foundation

public enum RelativeDateFormatter {

    /// 앱 번들의 preferred localization 을 기준으로 포매터를 만든다.
    /// iOS 앱별 언어 설정을 바꿔도 시스템 Locale.current 는 그대로라, 앱 UI 언어와 일치시키려면
    /// Bundle.main.preferredLocalizations 를 사용해야 한다.
    private static func currentFormatter() -> Foundation.RelativeDateTimeFormatter {
        let localeIdentifier = Bundle.main.preferredLocalizations.first ?? "en"
        let cached = Self.cached
        if cached?.localeIdentifier == localeIdentifier {
            return cached!.formatter
        }
        let formatter = Foundation.RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = Locale(identifier: localeIdentifier)
        Self.cached = (localeIdentifier, formatter)
        return formatter
    }

    nonisolated(unsafe) private static var cached: (localeIdentifier: String, formatter: Foundation.RelativeDateTimeFormatter)?

    /// Returns a relative date string like "5 min. ago", "yesterday", "Mar 5"
    public static func short(_ date: Date) -> String {
        currentFormatter().localizedString(for: date, relativeTo: Date())
    }
}
