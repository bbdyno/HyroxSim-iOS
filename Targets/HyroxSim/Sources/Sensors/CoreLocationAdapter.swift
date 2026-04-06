import CoreLocation
import HyroxKit

/// CoreLocation adapter for iOS.
/// Converts CLLocation updates to HyroxKit's LocationSample and streams them.
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
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
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
            // Skip invalid locations (CL signals invalid with negative accuracy)
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
        // Location errors are non-fatal — CL may recover on its own.
        // Serious errors (e.g., denied) are handled via authorization changes.
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
