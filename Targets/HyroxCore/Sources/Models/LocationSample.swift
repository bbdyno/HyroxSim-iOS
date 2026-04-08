//
//  LocationSample.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// A single GPS location measurement.
/// Pure value type — no CoreLocation dependency. The app layer converts
/// `CLLocation` → `LocationSample` via an adapter.
public struct LocationSample: Hashable, Sendable, Codable {
    public let timestamp: Date
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    /// Horizontal accuracy in meters
    public let horizontalAccuracy: Double
    /// Speed in m/s (nil if unavailable)
    public let speed: Double?
    /// Course heading in degrees (nil if unavailable)
    public let course: Double?

    public init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double,
        speed: Double? = nil,
        course: Double? = nil
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
    }
}
