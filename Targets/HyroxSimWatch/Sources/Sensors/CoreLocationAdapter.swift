//
//  CoreLocationAdapter.swift
//  HyroxSimWatch
//
//  Created by bbdyno on 4/7/26.
//

import CoreLocation
import HyroxCore

/// CoreLocation adapter for watchOS.
/// Converts CLLocation updates to HyroxKit's LocationSample and streams them.
///
/// Note: This shares the same logic as the iOS CoreLocationAdapter.
/// Both should be kept in sync when making changes. A shared target could
/// be introduced in a future refactor.
public final class CoreLocationAdapter: NSObject, LocationStreaming, CLLocationManagerDelegate, @unchecked Sendable {

    private let manager = CLLocationManager()
    private var continuation: AsyncStream<LocationSample>.Continuation?
    public let samples: AsyncStream<LocationSample>

    public private(set) var authorizationStatus: SensorAuthorizationStatus = .notDetermined
    private var isStarted = false
    private var authorizationContinuation: CheckedContinuation<Void, Error>?

    public override init() {
        var cont: AsyncStream<LocationSample>.Continuation!
        self.samples = AsyncStream(bufferingPolicy: .bufferingNewest(100)) { c in cont = c }
        super.init()
        self.continuation = cont
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        updateAuthorizationStatus(manager.authorizationStatus)
    }

    deinit {
        continuation?.finish()
    }

    // MARK: - LocationStreaming

    public func start() async throws {
        guard !isStarted else { return }

        if authorizationStatus == .notDetermined {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.authorizationContinuation = cont
                self.manager.requestWhenInUseAuthorization()
            }
        }

        guard authorizationStatus == .authorized else {
            throw SensorError.authorizationDenied
        }

        manager.startUpdatingLocation()
        isStarted = true
    }

    public func stop() {
        manager.stopUpdatingLocation()
        isStarted = false
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            guard location.horizontalAccuracy >= 0 else { continue }
            let sample = LocationSample(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                horizontalAccuracy: location.horizontalAccuracy,
                speed: location.speed >= 0 ? location.speed : nil,
                course: location.course >= 0 ? location.course : nil
            )
            continuation?.yield(sample)
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus(manager.authorizationStatus)

        if let authCont = authorizationContinuation {
            authorizationContinuation = nil
            if authorizationStatus == .authorized {
                authCont.resume()
            } else if authorizationStatus != .notDetermined {
                authCont.resume(throwing: SensorError.authorizationDenied)
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal — CL may recover.
    }

    // MARK: - Private

    private func updateAuthorizationStatus(_ clStatus: CLAuthorizationStatus) {
        switch clStatus {
        case .notDetermined:
            authorizationStatus = .notDetermined
        case .restricted:
            authorizationStatus = .restricted
        case .denied:
            authorizationStatus = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            authorizationStatus = .authorized
        @unknown default:
            authorizationStatus = .denied
        }
    }
}
