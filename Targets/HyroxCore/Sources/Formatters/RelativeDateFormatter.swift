//
//  RelativeDateFormatter.swift
//  HyroxCore
//
//  Created by bbdyno on 4/18/26.
//

import Foundation

public enum RelativeDateFormatter {

    private static let formatter: Foundation.RelativeDateTimeFormatter = {
        let f = Foundation.RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Returns a relative date string like "5 min. ago", "yesterday", "Mar 5"
    public static func short(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
