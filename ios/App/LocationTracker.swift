import CoreLocation
import Observation

/// Location stays on the device; recent pings are kept in memory only.
@MainActor
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var pings: [Ping] = []
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var backgroundTripTrackingEnabled: Bool
    var onPingsUpdated: (@MainActor ([Ping]) -> Void)?
    private let manager = CLLocationManager()
    private let window: TimeInterval = 180
    private var requestedAlwaysAuthorization = false
    private var alwaysAuthorizationRequestIssued = false

    private static let backgroundTrackingKey = "privacy.backgroundTripTracking"

    override init() {
        backgroundTripTrackingEnabled = UserDefaults.standard.bool(forKey: Self.backgroundTrackingKey)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.activityType = .otherNavigation
        manager.showsBackgroundLocationIndicator = false
        authorization = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
    }

    /// Requests Always permission only after the rider explicitly enables trip tracking.
    func setBackgroundTripTracking(_ enabled: Bool) {
        backgroundTripTrackingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.backgroundTrackingKey)
        guard enabled else {
            requestedAlwaysAuthorization = false
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
            manager.pausesLocationUpdatesAutomatically = true
            manager.distanceFilter = kCLDistanceFilterNone
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            requestedAlwaysAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestedAlwaysAuthorization = true
            alwaysAuthorizationRequestIssued = true
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        case .denied, .restricted:
            backgroundTripTrackingEnabled = false
            UserDefaults.standard.set(false, forKey: Self.backgroundTrackingKey)
        @unknown default:
            backgroundTripTrackingEnabled = false
        }
    }

    /// Background updates are enabled only during a rider-confirmed active trip.
    func beginTripTracking() {
        guard backgroundTripTrackingEnabled, manager.authorizationStatus == .authorizedAlways else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.distanceFilter = 25
        manager.startUpdatingLocation()
    }

    func endTripTracking() {
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.distanceFilter = kCLDistanceFilterNone
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.manager.startUpdatingLocation() }
            if status == .authorizedWhenInUse, self.requestedAlwaysAuthorization, !self.alwaysAuthorizationRequestIssued {
                self.alwaysAuthorizationRequestIssued = true
                self.manager.requestAlwaysAuthorization()
            } else if status == .authorizedAlways, self.requestedAlwaysAuthorization {
                self.requestedAlwaysAuthorization = false
                self.alwaysAuthorizationRequestIssued = false
            } else if status == .denied || status == .restricted {
                self.backgroundTripTrackingEnabled = false
                UserDefaults.standard.set(false, forKey: Self.backgroundTrackingKey)
                self.requestedAlwaysAuthorization = false
                self.alwaysAuthorizationRequestIssued = false
            }
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
            self.onPingsUpdated?(self.pings)
        }
    }
}
