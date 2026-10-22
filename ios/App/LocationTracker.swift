import CoreLocation
import Observation

/// Location stays on the device; recent pings are kept in memory only.
@MainActor
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var pings: [Ping] = []
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    private let window: TimeInterval = 180

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.activityType = .otherNavigation
        authorization = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let new = locations.filter { $0.horizontalAccuracy >= 0 }.map {
            Ping(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude, accuracyM: $0.horizontalAccuracy,
                 speedMps: $0.speed >= 0 ? $0.speed : nil, heading: $0.course >= 0 ? $0.course : nil, timestamp: $0.timestamp)
        }
        Task { @MainActor in
            let cutoff = Date().addingTimeInterval(-self.window)
            self.pings = (self.pings + new).filter { $0.timestamp >= cutoff }
        }
    }
}
