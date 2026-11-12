import CoreLocation
import MapKit
import Observation

enum PlanField { case from, to }

@MainActor
@Observable
final class PlannerModel {
    var from: PlanPoint?
    var to: PlanPoint?
    var fromMode: AccessMode = .walk { didSet { if fromMode != oldValue { invalidatePlan(); scheduleAutomaticPlan() } } }
    var toMode: AccessMode = .walk { didSet { if toMode != oldValue { invalidatePlan(); scheduleAutomaticPlan() } } }
    enum TimeMode: String, CaseIterable, Identifiable {
        case now = "Leave now", depart = "Depart at", arrive = "Arrive by"
        var id: String { rawValue }
    }
    var timeMode: TimeMode = .now { didSet { if timeMode != oldValue { invalidatePlan() } } }
    var departAt = Date() { didSet { if departAt != oldValue { invalidatePlan() } } }
    var fromText = ""
    var toText = ""
    var results: [Itinerary] = []
    var selectedId: UUID?
    var isPlanning = false
    var isResolving = false
    var error: String?
    private(set) var locationErrors: [PlanField: String] = [:]
    /// Set while the rider is tapping the map to drop a pin.
    var pickTarget: PlanField?
    var showSheet = false

    private let provider: TransitProvider
    private let location: LocationTracker
    private let searchLocation: @MainActor (String) async throws -> PlanPoint?
    private let accessLeg: @Sendable (AccessMode, CLLocationCoordinate2D, CLLocationCoordinate2D) async -> (seconds: TimeInterval, meters: Double)
    private var network: TransitNetwork?
    private var activePlanRequest: UUID?
    private var activeResolveRequest: UUID?
    private var formRevision = 0
    private struct SearchRequest {
        let id: UUID
        let text: String
        let task: Task<PlanPoint?, Error>
    }
    private var searches: [PlanField: SearchRequest] = [:]

    init(provider: TransitProvider, location: LocationTracker,
         searchLocation: @escaping @MainActor (String) async throws -> PlanPoint? = PlannerModel.searchLocation,
         accessLeg: @escaping @Sendable (AccessMode, CLLocationCoordinate2D, CLLocationCoordinate2D) async -> (seconds: TimeInterval, meters: Double) = PlannerModel.routedAccessLeg) {
        self.provider = provider
        self.location = location
        self.searchLocation = searchLocation
        self.accessLeg = accessLeg
    }

    var selected: Itinerary? { results.first { $0.id == selectedId } ?? results.first }

    var hasPlanContent: Bool {
        from != nil || to != nil
            || !fromText.isEmpty || !toText.isEmpty
            || !results.isEmpty || error != nil || pickTarget != nil || isPlanning || isResolving
    }

    func useMyLocation(_ field: PlanField) {
        guard let p = location.pings.last else { error = "Current location unavailable."; return }
        set(PlanPoint(name: "My location", lat: p.lat, lon: p.lon, isCurrentLocation: true), field)
    }

    func set(_ point: PlanPoint, _ field: PlanField) {
        invalidateResolve()
        apply(point, to: field)
    }

    private func apply(_ point: PlanPoint, to field: PlanField) {
        searches[field] = nil
        locationErrors[field] = nil
        invalidatePlan()
        switch field {
        case .from: from = point; fromText = point.name
        case .to: to = point; toText = point.name
        }
        scheduleAutomaticPlan()
    }

    func updateText(_ text: String, field: PlanField) {
        let current = field == .from ? fromText : toText
        guard text != current else { return }
        invalidateResolve()
        searches[field] = nil
        locationErrors[field] = nil
        invalidatePlan()
        error = nil
        switch field {
        case .from: fromText = text; from = nil
        case .to: toText = text; to = nil
        }
    }

    func setModeForBoth(_ mode: AccessMode) {
        fromMode = mode
        toMode = mode
    }

    private func invalidatePlan() {
        activePlanRequest = nil
        isPlanning = false
        results = []
        selectedId = nil
    }

    private func invalidateResolve() {
        formRevision += 1
        activeResolveRequest = nil
        isResolving = false
    }

    private func scheduleAutomaticPlan() {
        guard let from, let to else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.from == from, self.to == to,
                  self.fromText == from.name, self.toText == to.name,
                  !self.isPlanning, !self.isResolving, self.results.isEmpty else { return }
            await self.plan()
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
        invalidateResolve()
        searches.removeAll()
        let fromError = locationErrors[.from]
        locationErrors[.from] = locationErrors[.to]
        locationErrors[.to] = fromError
        invalidatePlan()
        (from, to) = (to, from)
        (fromText, toText) = (toText, fromText)
        (fromMode, toMode) = (toMode, fromMode)
        scheduleAutomaticPlan()
    }

    func clear() {
        invalidateResolve()
        searches.removeAll()
        locationErrors.removeAll()
        activePlanRequest = nil
        isPlanning = false
        from = nil
        to = nil
        fromText = ""
        toText = ""
        fromMode = .walk
        toMode = .walk
        timeMode = .now
        departAt = Date()
        results = []
        selectedId = nil
        error = nil
        pickTarget = nil
    }

    private static func searchLocation(_ text: String) async throws -> PlanPoint? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.region = MKCoordinateRegion(center: .init(latitude: 42.36, longitude: -71.06),
                                        span: .init(latitudeDelta: 1.2, longitudeDelta: 1.2))
        guard let item = try await MKLocalSearch(request: req).start().mapItems.first else { return nil }
        let c = item.placemark.coordinate
        return PlanPoint(name: item.name ?? text, lat: c.latitude, lon: c.longitude)
    }

    func search(_ field: PlanField) async {
        let text = field == .from ? fromText : toText
        let point = field == .from ? from : to
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, point?.name != text else { return }
        let request: SearchRequest
        if let existing = searches[field], existing.text == text {
            request = existing
        } else {
            request = SearchRequest(id: UUID(), text: text, task: Task { try await searchLocation(text) })
            searches[field] = request
        }
        do {
            let point = try await request.task.value
            guard searches[field]?.id == request.id, (field == .from ? fromText : toText) == text else { return }
            searches[field] = nil
            guard let point else { locationErrors[field] = "No match for \(text)."; return }
            apply(point, to: field)
        } catch {
            if searches[field]?.id == request.id {
                searches[field] = nil
                locationErrors[field] = "Search failed. Check your connection."
            }
        }
    }

    func resolveAndPlan() async {
        guard !isResolving, !isPlanning else { return }
        isResolving = true
        let requestID = UUID()
        activeResolveRequest = requestID
        let revision = formRevision
        defer {
            if activeResolveRequest == requestID {
                activeResolveRequest = nil
                isResolving = false
            }
        }
        await search(.from)
        guard revision == formRevision, from != nil else { return }
        await search(.to)
        guard revision == formRevision, to != nil else { return }
        await plan()
    }

    func plan() async {
        guard let a = from, let b = to, fromText == a.name, toText == b.name else {
            error = "Choose a start and destination."
            return
        }
        let requestID = UUID()
        activePlanRequest = requestID
        isPlanning = true
        error = nil
        results = []
        selectedId = nil
        defer {
            if activePlanRequest == requestID {
                activePlanRequest = nil
                isPlanning = false
            }
        }
        do {
            if network == nil {
                let loadedNetwork = try await provider.network()
                guard activePlanRequest == requestID else { return }
                network = loadedNetwork
            }
            guard let network else { return }
            let planner = TripPlanner(provider: provider, network: network, accessLeg: accessLeg)
            let plannedResults: [Itinerary]
            switch timeMode {
            case .now: plannedResults = try await planner.plan(from: a, to: b, fromMode: fromMode, toMode: toMode, departAt: Date())
            case .depart: plannedResults = try await planner.plan(from: a, to: b, fromMode: fromMode, toMode: toMode, departAt: max(departAt, Date()))
            case .arrive: plannedResults = try await planner.plan(from: a, to: b, fromMode: fromMode, toMode: toMode, arriveBy: departAt)
            }
            guard activePlanRequest == requestID else { return }
            results = plannedResults
            selectedId = plannedResults.first?.id
        } catch let e as PlannerError {
            if activePlanRequest == requestID { error = e.localizedDescription }
        } catch {
            if activePlanRequest == requestID { self.error = "Couldn't load transit data. Check your connection." }
        }
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
