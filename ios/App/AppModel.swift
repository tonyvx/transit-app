import Foundation
import SwiftUI
import MapKit
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var vehicles: [Vehicle] = []
    private(set) var alerts: [TransitAlert] = []
    private(set) var routes: [String: RouteInfo] = [:]
    private(set) var branches: [Branch] = []
    private(set) var routeTraces: [RouteTrace] = []
    private(set) var routeMapError: String?
    private(set) var routeDirections: [RouteDirection] = []
    private var stationsByKey: [String: [Station]] = [:]
    var highlightedVehicleId: String?
    var selectedStation: Station?
    private(set) var fetchedAt: Date?
    private(set) var error: String?
    var selectedVehicleId: String?
    private(set) var preferences: Preferences

    /// Saves preferences and applies them to the map immediately.
    func savePreferences(_ p: Preferences) {
        preferences = p
        p.save()
        Task { await loadStations() }
    }

    /// Routes and branches currently favorited within a line.
    private func favoriteChoices(for line: LineGroup) -> Set<String> {
        guard preferences.lines.contains(line) else { return [] }
        let all = routeChoiceIDs(for: line)
        let selected = preferences.routes.intersection(all)
        return selected.isEmpty ? all : selected
    }

    func isFavoriteRoute(_ routeId: String) -> Bool {
        guard let line = LineGroup(routeId: routeId) else { return false }
        let chosen = favoriteChoices(for: line)
        let routeBranches = Set(branches(for: routeId).map(\.id))
        return chosen.contains(routeId) || (!routeBranches.isEmpty && routeBranches.isSubset(of: chosen))
    }

    func isFavoriteBranch(_ branch: Branch) -> Bool {
        guard let line = LineGroup(routeId: branch.routeId) else { return false }
        let chosen = favoriteChoices(for: line)
        return chosen.contains(branch.id) || chosen.contains(branch.routeId)
    }

    func toggleFavoriteRoute(_ routeId: String) {
        guard let line = LineGroup(routeId: routeId) else { return }
        var chosen = favoriteChoices(for: line)
        let routeBranches = Set(branches(for: routeId).map(\.id))
        if isFavoriteRoute(routeId) {
            chosen.subtract(routeBranches.union([routeId]))
        } else {
            chosen.subtract(routeBranches)
            chosen.insert(routeId)
        }
        saveFavoriteChoices(chosen, for: line)
    }

    func toggleFavoriteBranch(_ branch: Branch) {
        guard let line = LineGroup(routeId: branch.routeId) else { return }
        var chosen = favoriteChoices(for: line)
        if isFavoriteBranch(branch) {
            if chosen.remove(branch.routeId) != nil {
                chosen.formUnion(branches(for: branch.routeId).map(\.id))
            }
            chosen.remove(branch.id)
        } else {
            chosen.insert(branch.id)
        }
        saveFavoriteChoices(chosen, for: line)
    }

    private func saveFavoriteChoices(_ chosen: Set<String>, for line: LineGroup) {
        let all = routeChoiceIDs(for: line)
        var updated = preferences
        updated.routes.subtract(all)
        if chosen.isEmpty {
            updated.lines.remove(line)
        } else {
            updated.lines.insert(line)
            // No explicit choices means the whole line.
            if chosen != all { updated.routes.formUnion(chosen) }
        }
        savePreferences(updated)
    }

    private func routeChoiceIDs(for line: LineGroup) -> Set<String> {
        Set(routes.keys.filter { LineGroup(routeId: $0) == line })
            .union(branches.filter { LineGroup(routeId: $0.routeId) == line }.map(\.id))
    }

    var favoriteLineGroups: [LineGroup] {
        preferences.lines.sorted { $0.rawValue < $1.rawValue }
    }

    var favoriteLineLabels: [FavoriteLineLabel] {
        favoriteLineGroups.flatMap { line in
            let allChoices = routeChoiceIDs(for: line)
            let selected = preferences.routes.intersection(allChoices)
            guard !selected.isEmpty else {
                let title = line == .commuter ? "Commuter Rail" : "\(line.rawValue) Line"
                return [FavoriteLineLabel(id: line.rawValue, title: title, line: line)]
            }
            return selected.sorted().map { choice in
                if let branch = branches.first(where: { $0.id == choice }) {
                    let routeName = routes[branch.routeId]?.name ?? branch.routeId
                    return FavoriteLineLabel(
                        id: choice,
                        title: "\(routeName) · \(branch.name)",
                        line: line
                    )
                }
                return FavoriteLineLabel(
                    id: choice,
                    title: routes[choice]?.name ?? choice,
                    line: line
                )
            }
        }
    }

    private var favoriteRouteIDs: Set<String> {
        Set(preferences.lines.flatMap { line in
            let choices = favoriteChoices(for: line)
            return routes(in: line).compactMap { route in
                let routeBranches = branches(for: route.id)
                return choices.contains(route.id) || routeBranches.contains(where: { choices.contains($0.id) })
                    ? route.id
                    : nil
            }
        })
    }

    func loadRouteTraces() async {
        guard routes.isEmpty || routeTraces.isEmpty || routeDirections.isEmpty else { return }
        if routeTraces.isEmpty, let cached = RouteCache.load() {
            routes = Dictionary(uniqueKeysWithValues: cached.routes.map { ($0.id, $0) })
            routeTraces = cached.traces
            routeDirections = cached.directions
            routeMapError = nil
            return
        }
        do {
            if routes.isEmpty {
                let loadedRoutes = try await provider.routes()
                routes = Dictionary(uniqueKeysWithValues: loadedRoutes.map { ($0.id, $0) })
            }
            async let traces = provider.routeTraces()
            async let directions = provider.routeDirections(routeIds: routes.keys.sorted())
            routeTraces = try await traces
            routeDirections = try await directions
            if routeTraces.isEmpty {
                routeMapError = "Route maps are unavailable."
            } else {
                routeMapError = nil
                if !routeDirections.isEmpty {
                    RouteCache.save(RouteSnapshot(savedAt: Date(), routes: Array(routes.values),
                                                  traces: routeTraces, directions: routeDirections))
                }
            }
        } catch {
            if routeTraces.isEmpty { routeMapError = "Can't load route maps. Check your connection." }
            else { routeMapError = "Can't load route direction details. Check your connection." }
        }
    }

    /// Non-selected lines whose first stop is ahead of the rider, keyed by route id.
    private(set) var nearbyStarts: [String: NearbyStart] = [:]
    private var routeStops: [String: [StopInfo]] = [:]
    private var routeOrigins: [String: [StopInfo]] = [:]
    private var driveCache: [String: (seconds: TimeInterval?, at: Date)] = [:]

    /// Alerts split into those for the rider's lines, those for other lines whose start is ahead of them, and the rest.
    var alertGroups: (mine: [TransitAlert], ahead: [TransitAlert], other: [TransitAlert]) {
        var mine: [TransitAlert] = [], ahead: [TransitAlert] = [], other: [TransitAlert] = []
        for a in alerts {
            if a.affectsAnyRoute(in: favoriteRouteIDs) { mine.append(a) }
            else if a.routeIds.contains(where: { nearbyStarts[$0] != nil }) { ahead.append(a) }
            else { other.append(a) }
        }
        return (mine, ahead, other)
    }

    func nearbyStart(for alert: TransitAlert) -> NearbyStart? {
        alert.routeIds.compactMap { nearbyStarts[$0] }.min { ($0.driveSeconds ?? .infinity) < ($1.driveSeconds ?? .infinity) }
    }

    /// For alerts on lines outside the preferences, finds lines whose first stop (in a selected direction) is the
    /// rider's nearest stop on that line, i.e. the line begins ahead of them, and estimates the drive there.
    func updateNearbyStarts() async {
        guard let me = location.pings.last else { nearbyStarts = [:]; return }
        let dirs = preferences.directions.isEmpty ? Direction.allCases : Array(preferences.directions)
        let candidates = Set(alerts.flatMap(\.routeIds).filter { id in
            guard let g = LineGroup(routeId: id) else { return false }
            return !preferences.lines.contains(g)
        })
        var result: [String: NearbyStart] = [:]
        for routeId in candidates {
            if routeStops[routeId] == nil { routeStops[routeId] = try? await provider.stations(routeIds: [routeId]) }
            guard let stops = routeStops[routeId],
                  let nearest = stops.min(by: { sqDist($0.lat, $0.lon, me.lat, me.lon) < sqDist($1.lat, $1.lon, me.lat, me.lon) }) else { continue }
            var best: NearbyStart?
            for d in dirs {
                let key = "\(routeId)|\(d.rawValue)"
                if routeOrigins[key] == nil { routeOrigins[key] = try? await provider.origins(routeId: routeId, directionId: d.rawValue) }
                guard let origin = routeOrigins[key]?.first(where: { $0.id == nearest.id }) else { continue }
                let secs = await driveSeconds(to: origin, from: me)
                if best == nil || (secs ?? .infinity) < (best?.driveSeconds ?? .infinity) {
                    best = NearbyStart(routeId: routeId, stationName: origin.name, direction: d, driveSeconds: secs)
                }
            }
            if let best { result[routeId] = best }
        }
        nearbyStarts = result
    }

    private func driveSeconds(to stop: StopInfo, from me: Ping) async -> TimeInterval? {
        // Re-estimate only after a few minutes, or when the rider has moved a few hundred metres.
        let key = "\(stop.id)|\(Int(me.lat * 300))|\(Int(me.lon * 300))"
        if let c = driveCache[key], Date().timeIntervalSince(c.at) < 180 { return c.seconds }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: me.lat, longitude: me.lon)))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: stop.lat, longitude: stop.lon)))
        req.transportType = .automobile
        let secs = try? await MKDirections(request: req).calculateETA().expectedTravelTime
        driveCache[key] = (secs, Date())
        return secs
    }

    /// Lines offered as legend chips: only those chosen in preferences.
    /// Per line, ids of trains that have not yet reached the rider's nearest station on that line.
    /// A missing entry means unknown (no location or stations yet), in which case the line is not filtered.
    private var approaching: [LineGroup: Set<String>] = [:]

    func updateApproaching() async {
        guard preferences.onlyApproaching, let me = location.pings.last else { approaching = [:]; return }
        var result: [LineGroup: Set<String>] = [:]
        for line in preferences.lines {
            guard let nearest = (stationsByKey[stationKey(for: line)] ?? []).min(by: {
                sqDist($0.lat, $0.lon, me.lat, me.lon) < sqDist($1.lat, $1.lon, me.lat, me.lon)
            }) else { continue }
            guard let list = try? await provider.arrivals(stopId: nearest.stopId, routeIds: routeIdsToShow(in: line)) else { continue }
            let cutoff = Date().addingTimeInterval(-30)
            result[line] = Set(list.filter { $0.time >= cutoff }.compactMap(\.vehicleId))
        }
        approaching = result
    }

    private func sqDist(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let dLat = aLat - bLat
        let dLon = (aLon - bLon) * cos(aLat * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    var visibleVehicles: [Vehicle] {
        VehicleFilter(enabledLines: preferences.lines, enabledRoutes: preferences.routes, enabledDirections: preferences.directions,
                      approaching: approaching, routes: routes, branches: branches).apply(to: vehicles)
    }

    /// Routes belonging to a line group, in display order.
    func routes(in line: LineGroup) -> [RouteInfo] {
        routes.values.filter { LineGroup(routeId: $0.id) == line }.sorted { $0.name < $1.name }
    }

    /// Stations to draw: for each enabled line, those on its selected routes (or on all its routes if none selected).
    var visibleStations: [Station] {
        preferences.lines.flatMap { stationsByKey[stationKey(for: $0)] ?? [] }
    }

    private func routeIdsToShow(in line: LineGroup) -> [String] {
        let choices = favoriteChoices(for: line)
        return routes(in: line).filter { route in
            choices.contains(route.id) || branches(for: route.id).contains(where: { choices.contains($0.id) })
        }.map(\.id)
    }

    private func stationKey(for line: LineGroup) -> String { "\(line.rawValue):\(routeIdsToShow(in: line).joined(separator: ","))" }

    /// Changes whenever the set of stations to show changes, so the view can reload them.
    var stationRequestKey: String { preferences.lines.sorted { $0.rawValue < $1.rawValue }.map(stationKey(for:)).joined(separator: "|") }

    func loadStations() async {
        for line in preferences.lines {
            let key = stationKey(for: line)
            let ids = routeIdsToShow(in: line)
            guard stationsByKey[key] == nil, !ids.isEmpty else { continue }
            if let stops = try? await provider.stations(routeIds: ids) {
                stationsByKey[key] = stops.map { Station(stopId: $0.id, name: $0.name, lat: $0.lat, lon: $0.lon, line: line) }
            }
        }
        await updateApproaching()
    }

    /// Upcoming arrivals at a station for its line's routes, labeled by train.
    func arrivals(at station: Station) async -> [Arrival] {
        let ids = routeIdsToShow(in: station.line)
        let now = Date().addingTimeInterval(-30)
        let list = (try? await provider.arrivals(stopId: station.stopId, routeIds: ids)) ?? []
        return list.filter { $0.time >= now }
    }

    func trainLabel(_ vehicleId: String) -> String {
        vehicles.first { $0.id == vehicleId }.flatMap(\.label) ?? vehicleId
    }

    /// Highlights a train with a halo and centers the map on it.
    func highlight(vehicleId: String) {
        guard vehicles.contains(where: { $0.id == vehicleId }) else { return }
        highlightedVehicleId = vehicleId
        selectedVehicleId = vehicleId
    }

    func branches(for routeId: String) -> [Branch] { branches.filter { $0.routeId == routeId } }

    let provider: TransitProvider
    let location: LocationTracker
    let planner: PlannerModel
    let favorites = FavoritesModel()
    let journey = JourneyTracker()

    func routeColor(_ routeId: String?) -> Color {
        if let routeId, let hex = routes[routeId]?.color, let v = UInt32(hex.dropFirst(), radix: 16) {
            return Color(red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255)
        }
        return .gray
    }

    init() {
        let provider = MBTAClient()
        let location = LocationTracker()
        self.provider = provider
        self.location = location
        planner = PlannerModel(provider: provider, location: location)
        let p = Preferences.load()
        preferences = p
        location.onPingsUpdated = { [weak self] pings in
            guard let self else { return }
            Task {
                await self.journey.evaluate(
                    itinerary: self.planner.selected,
                    vehicles: self.vehicles,
                    pings: pings,
                    routeNames: self.routes.mapValues(\.name),
                    fetchedAt: self.fetchedAt ?? .distantPast
                )
            }
        }
    }

    var myTrain: TrainMatch? { TrainMatcher.match(pings: location.pings, vehicles: vehicles) }
    /// Vehicles drawn on the map: the filtered set plus a highlighted train even if its line is filtered out.
    var mapVehicles: [Vehicle] {
        let shown = visibleVehicles
        guard let h = highlightedVehicleId, !shown.contains(where: { $0.id == h }), let v = vehicles.first(where: { $0.id == h }) else { return shown }
        return shown + [v]
    }

    var selected: Vehicle? { mapVehicles.first { $0.id == selectedVehicleId } }

    /// False while the app is in the background, so polling stops and costs no battery or data.
    var isActive = true
    /// True when the last vehicle refresh failed, so the map is showing stale positions.
    var isOffline: Bool { error != nil }

    /// Seconds between vehicle refreshes: fast while trains are shown, slow when nothing on the map needs them.
    var refreshInterval: Duration {
        preferences.lines.isEmpty && planner.selected == nil ? .seconds(20) : .seconds(5)
    }

    func refreshLoop() async {
        if routes.isEmpty, let r = try? await provider.routes() { routes = Dictionary(uniqueKeysWithValues: r.map { ($0.id, $0) }) }
        if branches.isEmpty, let b = try? await provider.branches() { branches = b }
        if routeTraces.isEmpty || routeDirections.isEmpty { await loadRouteTraces() }
        var tick = 0
        while !Task.isCancelled {
            guard isActive else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            do {
                vehicles = try await provider.vehicles()
                fetchedAt = Date()
                await journey.evaluate(itinerary: planner.selected, vehicles: vehicles, pings: location.pings,
                                       routeNames: routes.mapValues(\.name), fetchedAt: fetchedAt ?? Date())
                if tick % 6 == 0, routeTraces.isEmpty || routeDirections.isEmpty { await loadRouteTraces() }
                if tick % 3 == 0 { await updateApproaching() }
                if tick % 6 == 0 { alerts = try await provider.alerts(); await updateNearbyStarts() }
                error = nil
            } catch {
                self.error = "No connection"
            }
            tick += 1
            try? await Task.sleep(for: refreshInterval)
        }
    }
}
