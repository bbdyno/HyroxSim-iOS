//
//  LocalizedDecimalFormatter.swift
//  HyroxSim
//
//  Created by bbdyno on 7/20/26.
//

import Foundation

/// 사용자가 직접 입력하는 수치의 허용 범위.
/// 범위를 벗어난 값은 저장을 막거나 잘라내어 `Double` → `Int` 변환 트랩을 예방한다.
enum NumericInputLimits {
    /// 런/스테이션 거리 (m)
    static let distanceMeters: ClosedRange<Double> = 1...100_000
    /// 스테이션 반복 횟수
    static let reps: ClosedRange<Double> = 1...10_000
    /// 목표 시간 (초, 최대 24시간)
    static let durationSeconds: ClosedRange<Double> = 0...86_400
    /// 중량 (kg)
    static let weightKilograms: ClosedRange<Double> = 0...1_000
}

enum LocalizedDecimalFormatter {

    static func value(from text: String, locale: Locale = .current) -> Double? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }

        let formatter = makeFormatter(locale: locale)
        return formatter.number(from: trimmedText)?.doubleValue ?? Double(trimmedText)
    }

    /// 유한한 값만 통과시킨다. `inf` / `nan` 같은 비정상 입력은 nil.
    static func finiteValue(from text: String, locale: Locale = .current) -> Double? {
        guard let parsed = value(from: text, locale: locale), parsed.isFinite else { return nil }
        return parsed
    }

    /// 값을 허용 범위 안으로 자른다. NaN 은 하한으로 처리한다.
    static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard !value.isNaN else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// `Double` → `Int` 변환에서 트랩이 발생하지 않도록 방어한다.
    /// NaN 은 `lowerBound`, ±무한대와 `Int` 표현 범위를 벗어난 값은 상·하한으로 자른다.
    static func safeInt(_ value: Double, lowerBound: Int = 0, upperBound: Int = Int.max) -> Int {
        guard !value.isNaN else { return lowerBound }
        guard let exact = Int(exactly: value.rounded(.towardZero)) else {
            return value < 0 ? lowerBound : upperBound
        }
        return min(max(exact, lowerBound), upperBound)
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
