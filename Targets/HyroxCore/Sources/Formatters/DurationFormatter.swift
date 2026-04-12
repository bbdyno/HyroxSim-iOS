//
//  DurationFormatter.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

public enum DurationFormatter {

    /// Formats seconds as "H:MM:SS" (e.g., 3661 → "1:01:01")
    public static func hms(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    /// Formats seconds as "MM:SS" (e.g., 125 → "02:05")
    public static func ms(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Formats signed seconds as "+M:SS" or "-M:SS".
    public static func signedMs(_ seconds: TimeInterval) -> String {
        let sign = seconds >= 0 ? "+" : "-"
        let total = Int(abs(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%@%d:%02d", sign, m, s)
    }

    /// Formats pace (sec/km) as "5'42\" /km". Returns "—" for nil.
    public static func pace(_ secondsPerKm: Double?) -> String {
        guard let sPerKm = secondsPerKm, sPerKm.isFinite, sPerKm > 0 else { return "—" }
        let total = Int(sPerKm)
        let m = total / 60
        let s = total % 60
        return String(format: "%d'%02d\" /km", m, s)
    }
}
