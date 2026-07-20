//
//  LocalizedDecimalFormatter.swift
//  HyroxSim
//
//  Created by bbdyno on 7/20/26.
//

import Foundation

enum LocalizedDecimalFormatter {

    static func value(from text: String, locale: Locale = .current) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let formatter = makeFormatter(locale: locale)
        return formatter.number(from: trimmedText)?.doubleValue ?? Double(trimmedText)
    }

    static func string(from value: Double, locale: Locale = .current) -> String {
        let formatter = makeFormatter(locale: locale)
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func makeFormatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.isLenient = false
        return formatter
    }
}
