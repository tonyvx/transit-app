import CoreLocation
import Foundation

struct TripMapVisibility {
    let plannedRouteIDs: Set<String>
    let plannedStationIDs: Set<String>
    let hideOtherLines: Bool

    private var filtering: Bool { hideOtherLines && !plannedRouteIDs.isEmpty }

    var fadesRouteTraces: Bool { filtering }

    func showsRoute(_ routeID: String) -> Bool {
        !filtering || plannedRouteIDs.contains(routeID)
    }

    func showsStation(_ station: Station) -> Bool {
        !filtering || (plannedStationIDs.contains(station.stopId) &&
            plannedRouteIDs.contains { LineGroup(routeId: $0) == station.line })
    }
}

struct TripRoutePath {
    private struct Projection {
        let progress: Double
        let coordinate: CLLocationCoordinate2D
        let distanceSquared: Double
    }

    /// Selects a shape that passes all stops in order and clips it at the boarding and alighting stops.
    static func coordinates(stops: [TripStop], traces: [RouteTrace]) -> [CLLocationCoordinate2D]? {
        guard stops.count >= 2 else { return nil }
        var best: (score: Double, coordinates: [CLLocationCoordinate2D])?
        for trace in traces where trace.coordinates.count >= 2 {
            let points = trace.coordinates
            let projections = stops.map { stop -> Projection in
                let latScale = 111_195.0
                let lonScale = latScale * cos(stop.lat * .pi / 180)
                var nearest: Projection?
                for i in 0..<(points.count - 1) {
                    let a = points[i], b = points[i + 1]
                    let ax = (a.longitude - stop.lon) * lonScale, ay = (a.latitude - stop.lat) * latScale
                    let dx = (b.longitude - a.longitude) * lonScale, dy = (b.latitude - a.latitude) * latScale
                    let lengthSquared = dx * dx + dy * dy
                    let fraction = lengthSquared == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
                    let x = ax + fraction * dx, y = ay + fraction * dy
                    let distanceSquared = x * x + y * y
                    if distanceSquared < (nearest?.distanceSquared ?? .infinity) {
                        nearest = Projection(progress: Double(i) + fraction,
                            coordinate: CLLocationCoordinate2D(latitude: a.latitude + fraction * (b.latitude - a.latitude),
                                                               longitude: a.longitude + fraction * (b.longitude - a.longitude)),
                            distanceSquared: distanceSquared)
                    }
                }
                return nearest!
            }
            guard projections.allSatisfy({ $0.distanceSquared <= 250 * 250 }),
                  let first = projections.first, let last = projections.last,
                  first.progress != last.progress else { continue }
            let forward = last.progress > first.progress
            guard zip(projections, projections.dropFirst()).allSatisfy({
                forward ? $0.progress <= $1.progress : $0.progress >= $1.progress
            }) else { continue }
            let lower = min(first.progress, last.progress), upper = max(first.progress, last.progress)
            let intermediate = points.indices.filter { Double($0) > lower && Double($0) < upper }
                .map { CLLocationCoordinate2D(latitude: points[$0].latitude, longitude: points[$0].longitude) }
            let segment = [first.coordinate] + (forward ? intermediate : intermediate.reversed()) + [last.coordinate]
            let score = projections.reduce(0) { $0 + $1.distanceSquared }
            if score < (best?.score ?? .infinity) { best = (score, segment) }
        }
        return best?.coordinates
    }
}

/// Decides which vehicles to draw, given the rider's chip, route and direction selections.
struct VehicleFilter: Sendable {
    var enabledLines: Set<LineGroup> = []
    var enabledRoutes: Set<String> = []
    var enabledDirections: Set<Direction> = []
    /// Per line, ids of trains that have not yet passed the rider. A missing line means unknown, so it is not filtered.
    var approaching: [LineGroup: Set<String>] = [:]
    var routes: [String: RouteInfo] = [:]
    var branches: [Branch] = []

    func apply(to vehicles: [Vehicle]) -> [Vehicle] {
        vehicles.filter { v in
            guard let g = LineGroup(routeId: v.routeId), enabledLines.contains(g) else { return false }
            if let ahead = approaching[g], !ahead.contains(v.id) { return false }
            // A line restricts to its selected routes and branches; with none selected it shows everything.
            let routeIds = Set(routes.keys.filter { LineGroup(routeId: $0) == g })
            let chosenRoutes = routeIds.intersection(enabledRoutes)
            let chosenBranches = Set(branches.filter { routeIds.contains($0.routeId) }.map(\.id)).intersection(enabledRoutes)
            if !chosenRoutes.isEmpty || !chosenBranches.isEmpty {
                let ok = chosenRoutes.contains(v.routeId) || (v.branchId.map(chosenBranches.contains) ?? false)
                if !ok { return false }
            }
            // No direction selected means no direction restriction.
            guard !enabledDirections.isEmpty, let d = v.directionId.flatMap(Direction.init(rawValue:)) else { return true }
            return enabledDirections.contains(d)
        }
    }
}
