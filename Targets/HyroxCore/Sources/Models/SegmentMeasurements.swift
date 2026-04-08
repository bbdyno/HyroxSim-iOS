//
//  SegmentMeasurements.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Raw measurement data collected during a single segment.
/// Provides computed properties for derived values (distance, pace, heart rate stats).
public struct SegmentMeasurements: Hashable, Sendable, Codable {
    public var locationSamples: [LocationSample]
    public var heartRateSamples: [HeartRateSample]

    public init(
        locationSamples: [LocationSample] = [],
        heartRateSamples: [HeartRateSample] = []
    ) {
        self.locationSamples = locationSamples
        self.heartRateSamples = heartRateSamples
    }

    // MARK: - Location Derived

    /// Cumulative distance in meters between adjacent GPS points.
    /// Points with `horizontalAccuracy > 30` are skipped (noise cutoff).
    /// Assumes samples are sorted by timestamp (caller responsibility).
    public var distanceMeters: Double {
        let filtered = locationSamples.filter { $0.horizontalAccuracy <= 30 }
        guard filtered.count >= 2 else { return 0 }

        var total: Double = 0
        for i in 1..<filtered.count {
            total += haversineDistance(from: filtered[i - 1], to: filtered[i])
        }
        return total
    }

    /// Average pace in seconds per kilometer.
    /// Returns nil if distance is effectively zero.
    /// - Parameter activeDuration: Active exercise time in seconds (excluding paused time)
    public func averagePaceSecondsPerKm(activeDuration: TimeInterval) -> Double? {
        let km = distanceMeters / 1000.0
        guard km > 0.001 else { return nil } // avoid division by near-zero
        return activeDuration / km
    }

    // MARK: - Heart Rate Derived

    /// Average heart rate across all samples. Nil if no samples.
    public var averageHeartRate: Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        let sum = heartRateSamples.reduce(0) { $0 + $1.bpm }
        return sum / heartRateSamples.count
    }

    /// Maximum heart rate. Nil if no samples.
    public var maxHeartRate: Int? {
        heartRateSamples.map(\.bpm).max()
    }

    /// Minimum heart rate. Nil if no samples.
    public var minHeartRate: Int? {
        heartRateSamples.map(\.bpm).min()
    }
}

// MARK: - Haversine

/// Haversine distance between two location samples in meters.
/// Uses the Earth's mean radius (6,371,000 m).
func haversineDistance(from a: LocationSample, to b: LocationSample) -> Double {
    let earthRadius: Double = 6_371_000 // meters

    let lat1 = a.latitude * .pi / 180
    let lat2 = b.latitude * .pi / 180
    let dLat = (b.latitude - a.latitude) * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180

    let h = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
    let c = 2 * atan2(sqrt(h), sqrt(1 - h))

    return earthRadius * c
}
