import Foundation

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
