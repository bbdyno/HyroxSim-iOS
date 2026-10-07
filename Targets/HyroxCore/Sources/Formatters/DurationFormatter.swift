//
//  DurationFormatter.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

public enum DurationFormatter {

    /// 표시 가능한 최대 초 (9999:59:59). 이보다 큰 값은 잘라서 포맷한다.
    static let maxDisplayableSeconds = 35_999_999

    /// `Double` → `Int` 변환에서 트랩이 발생하지 않도록 방어한다.
    /// NaN 은 `lowerBound`, ±무한대와 `Int` 표현 범위를 벗어난 값은 상·하한으로 자른다.
    static func safeInt(_ value: Double, lowerBound: Int = 0, upperBound: Int = Int.max) -> Int {
        guard !value.isNaN else { return lowerBound }
        guard let exact = Int(exactly: value.rounded(.towardZero)) else {
            return value < 0 ? lowerBound : upperBound
        }
        return min(max(exact, lowerBound), upperBound)
    }

    /// Formats seconds as "H:MM:SS" (e.g., 3661 → "1:01:01")
    public static func hms(_ seconds: TimeInterval) -> String {
        let total = safeInt(seconds, upperBound: maxDisplayableSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    /// Formats seconds as "MM:SS" (e.g., 125 → "02:05")
    public static func ms(_ seconds: TimeInterval) -> String {
        let total = safeInt(seconds, upperBound: maxDisplayableSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Formats signed seconds as "+M:SS" or "-M:SS".
    public static func signedMs(_ seconds: TimeInterval) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let total = safeInt(abs(seconds), upperBound: maxDisplayableSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%@%d:%02d", sign, m, s)
    }

    /// Formats pace (sec/km) as "5'42\" /km". Returns "—" for nil.
    public static func pace(_ secondsPerKm: Double?) -> String {
        guard let sPerKm = secondsPerKm, sPerKm.isFinite, sPerKm > 0 else { return "—" }
        let total = safeInt(sPerKm, upperBound: maxDisplayableSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d'%02d\" /km", m, s)
    }
}
