//
//  LocationStreaming.swift
//  HyroxKit
//
//  Created by bbdyno on 4/7/26.
//

import Foundation

/// Abstraction over a GPS location provider.
/// Implemented by platform-specific adapters (CoreLocationAdapter on iOS/watchOS).
/// HyroxKit does NOT import CoreLocation — this protocol keeps the boundary clean.
public protocol LocationStreaming: AnyObject, Sendable {
    /// Stream of location samples. Values flow only after `start()`.
    var samples: AsyncStream<LocationSample> { get }

    /// Requests authorization (if needed) and begins location updates.
    /// Idempotent — calling on an already-started stream is a no-op.
    func start() async throws

    /// Stops location updates. The stream remains valid for future reuse.
    func stop()

    /// Current authorization status.
    var authorizationStatus: SensorAuthorizationStatus { get }
}
