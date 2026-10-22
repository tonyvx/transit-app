import CoreLocation
import MapKit
import Observation

enum PlanField { case from, to }

@MainActor
@Observable
final class PlannerModel {
    var from: PlanPoint?
    var to: PlanPoint?
    var fromMode: AccessMode = .walk
    var toMode: AccessMode = .walk
    enum TimeMode: String, CaseIterable, Identifiable {
        case now = "Leave now", depart = "Depart at", arrive = "Arrive by"
        var id: String { rawValue }
    }
    var timeMode: TimeMode = .now
    var departAt = Date()
    var fromText = ""
    var toText = ""
    var results: [Itinerary] = []
    var selectedId: UUID?
    var isPlanning = false
    var error: String?
    /// Set while the rider is tapping the map to drop a pin.
    var pickTarget: PlanField?
    var showSheet = false

    private let provider: TransitProvider
    private let location: LocationTracker
    private var network: TransitNetwork?

    init(provider: TransitProvider, location: LocationTracker) {
        self.provider = provider
        self.location = location
    }

    var selected: Itinerary? { results.first { $0.id == selectedId } ?? results.first }

    func useMyLocation(_ field: PlanField) {
        guard let p = location.pings.last else { error = "Current location unavailable."; return }
        set(PlanPoint(name: "My location", lat: p.lat, lon: p.lon, isCurrentLocation: true), field)
    }

    func set(_ point: PlanPoint, _ field: PlanField) {
        switch field {
        case .from: from = point; fromText = point.name
        case .to: to = point; toText = point.name
        }
    }

    func dropPin(_ c: CLLocationCoordinate2D) {
        guard let field = pickTarget else { return }
        pickTarget = nil
        set(PlanPoint(name: "Dropped pin", lat: c.latitude, lon: c.longitude), field)
        showSheet = true
    }

    func savedTrip(name: String? = nil) -> SavedTrip? {
        guard let a = from, let b = to else { return nil }
        return SavedTrip(name: name ?? "\(a.name) → \(b.name)", fromName: a.name, fromLat: a.lat, fromLon: a.lon, fromIsCurrentLocation: a.isCurrentLocation,
                         toName: b.name, toLat: b.lat, toLon: b.lon, toIsCurrentLocation: b.isCurrentLocation, fromMode: fromMode.rawValue, toMode: toMode.rawValue)
    }

    /// Loads a saved trip into the form. Endpoints that were "My location" are re-read from the GPS.
    func load(_ t: SavedTrip) {
        set(PlanPoint(name: t.fromName, lat: t.fromLat, lon: t.fromLon, isCurrentLocation: t.fromIsCurrentLocation), .from)
        set(PlanPoint(name: t.toName, lat: t.toLat, lon: t.toLon, isCurrentLocation: t.toIsCurrentLocation), .to)
        if t.fromIsCurrentLocation { useMyLocation(.from) }
        if t.toIsCurrentLocation { useMyLocation(.to) }
        fromMode = AccessMode(rawValue: t.fromMode) ?? .walk
        toMode = AccessMode(rawValue: t.toMode) ?? .walk
        timeMode = .now
    }

    func swap() {
        (from, to) = (to, from)
        (fromText, toText) = (toText, fromText)
        (fromMode, toMode) = (toMode, fromMode)
    }

    func search(_ field: PlanField) async {
        let text = field == .from ? fromText : toText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.region = MKCoordinateRegion(center: .init(latitude: 42.36, longitude: -71.06),
                                        span: .init(latitudeDelta: 1.2, longitudeDelta: 1.2))
        do {
            guard let item = try await MKLocalSearch(request: req).start().mapItems.first else { error = "No match for \(text)."; return }
            let c = item.placemark.coordinate
            error = nil
            set(PlanPoint(name: item.name ?? text, lat: c.latitude, lon: c.longitude), field)
        } catch { self.error = "Search failed." }
    }

    func plan() async {
        guard let a = from, let b = to else { error = "Choose a start and destination."; return }
        isPlanning = true
        error = nil
        results = []
        defer { isPlanning = false }
        do {
            if network == nil { network = try await provider.network() }
            guard let network else { return }
            let planner = TripPlanner(provider: provider, network: network, accessLeg: PlannerModel.routedAccessLeg)
            switch timeMode {
            case .now: results = try await planner.plan(from: a, to: b, fromMode: fromMode, toMode: toMode, departAt: Date())
            case .depart: results = try await planner.plan(from: a, to: b, fromMode: fromMode, toMode: toMode, departAt: max(departAt, Date()))
            case .arrive: results = try await planner.plan(from: a, to: b, fromMode: fromMode, toMode: toMode, arriveBy: departAt)
            }
            selectedId = results.first?.id
        } catch let e as PlannerError { error = e.localizedDescription }
        catch { self.error = "Couldn't load transit data. Check your connection." }
    }

    /// Uses Apple Maps for walking and driving. Apple has no bike or scooter routing, so those use the walking distance at typical speed.
    nonisolated static let routedAccessLeg: @Sendable (AccessMode, CLLocationCoordinate2D, CLLocationCoordinate2D) async -> (seconds: TimeInterval, meters: Double) = { mode, a, b in
        let fallback = await TripPlanner.estimatedAccessLeg(mode, a, b)
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        req.transportType = mode == .car ? .automobile : .walking
        guard let route = try? await MKDirections(request: req).calculate().routes.first else { return fallback }
        switch mode {
        case .walk, .car: return (route.expectedTravelTime + mode.overheadSeconds, route.distance)
        case .bike, .scooter: return (route.distance / mode.speedMps + mode.overheadSeconds, route.distance)
        }
    }
}
