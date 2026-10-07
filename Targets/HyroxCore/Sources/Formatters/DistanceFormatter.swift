//
//  DistanceFormatter.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

public enum DistanceFormatter {

    /// Formats meters as "1.23 km" (>= 1000m) or "240 m" (< 1000m)
    ///
    /// NaN, 무한대, Int 범위를 넘는 값이 들어와도 트랩하지 않고 클램프한다.
    public static func short(_ meters: Double) -> String {
        guard meters.isFinite else { return "0 m" }
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        } else {
            return "\(DurationFormatter.safeInt(meters, lowerBound: Int.min)) m"
        }
    }
}
