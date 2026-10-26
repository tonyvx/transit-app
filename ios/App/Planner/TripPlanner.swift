import CoreLocation
import Foundation

/// Plans door-to-door trips: an access leg by walk, bike, scooter or car, MBTA rides and transfers, and an egress leg.
struct TripPlanner {
    let provider: TransitProvider
    let network: TransitNetwork
    let router: Router
    /// Seconds and metres for an access leg. Replaceable so tests and offline use can fall back to estimates.
    let accessLeg: @Sendable (AccessMode, CLLocationCoordinate2D, CLLocationCoordinate2D) async -> (seconds: TimeInterval, meters: Double)

    static let candidateStations = 5
    static let maxItineraries = 3
    /// Routes are ranked by typical cost, but some may not run on the chosen day, so spare ones are tried.
    static let maxAttempts = 8

    init(provider: TransitProvider, network: TransitNetwork,
         accessLeg: @escaping @Sendable (AccessMode, CLLocationCoordinate2D, CLLocationCoordinate2D) async -> (seconds: TimeInterval, meters: Double) = TripPlanner.estimatedAccessLeg) {
        self.provider = provider
        self.network = network
        self.router = Router(network: network)
        self.accessLeg = accessLeg
    }

    static let estimatedAccessLeg: @Sendable (AccessMode, CLLocationCoordinate2D, CLLocationCoordinate2D) async -> (seconds: TimeInterval, meters: Double) = { mode, a, b in
        let d = Geo.distanceM(a.latitude, a.longitude, b.latitude, b.longitude)
        return (mode.estimate(distanceM: d), d * AccessMode.circuity)
    }

    private func candidates(near p: PlanPoint, mode: AccessMode) -> [(NetStation, Double)] {
        let near = router.nearestStations(lat: p.lat, lon: p.lon)
        let inReach = near.filter { $0.distanceM <= mode.maxDistanceM }.prefix(Self.candidateStations)
        return inReach.map { ($0.station, mode.estimate(distanceM: $0.distanceM)) }
    }

    func plan(from a: PlanPoint, to b: PlanPoint, fromMode: AccessMode, toMode: AccessMode, departAt: Date) async throws -> [Itinerary] {
        let starts = candidates(near: a, mode: fromMode)
        let ends = candidates(near: b, mode: toMode)
        guard !starts.isEmpty else { throw PlannerError.noStationsNear("the start") }
        guard !ends.isEmpty else { throw PlannerError.noStationsNear("the destination") }

        let targets = Dictionary(ends.map { ($0.0.id, $0.1) }, uniquingKeysWith: min)
        var plans: [String: RoutePlan] = [:]
        for (station, cost) in starts {
            guard let p = router.plan(from: station.id, startCost: cost, targets: targets) else { continue }
            if plans[p.signature] == nil || plans[p.signature]!.cost > p.cost { plans[p.signature] = p }
        }
        let ranked = plans.values.sorted { $0.cost < $1.cost }.prefix(Self.maxAttempts)
        guard !ranked.isEmpty else { throw PlannerError.noRoute }

        var out: [Itinerary] = []
        for p in ranked {
            if let it = try? await resolve(p, from: a, to: b, fromMode: fromMode, toMode: toMode, departAt: departAt) { out.append(it) }
            if out.count == Self.maxItineraries { break }
        }
        guard !out.isEmpty else { throw PlannerError.noService }
        return out.sorted { $0.arriveAt < $1.arriveAt }
    }

    /// Finds trips that reach the destination by `arriveBy`, leaving as late as possible.
    /// Works by planning forward from earlier and later start times and keeping the latest trips that still arrive in time.
    func plan(from a: PlanPoint, to b: PlanPoint, fromMode: AccessMode, toMode: AccessMode, arriveBy: Date, now: Date = Date()) async throws -> [Itinerary] {
        guard arriveBy > now else { throw PlannerError.noArrival }
        var start = max(now, arriveBy.addingTimeInterval(-90 * 60))
        var valid: [Itinerary] = []
        var lastError: Error = PlannerError.noService
        for _ in 0..<6 {
            do {
                let found = try await plan(from: a, to: b, fromMode: fromMode, toMode: toMode, departAt: start)
                let ok = found.filter { $0.arriveAt <= arriveBy }
                valid += ok
                guard let latest = ok.map(\.leaveBy).max() else {
                    // Nothing arrives in time from this start. Starting earlier is the only way to catch an earlier train.
                    if valid.isEmpty, start > now { start = max(now, start.addingTimeInterval(-60 * 60)); continue } else { break }
                }
                start = latest.addingTimeInterval(60)
            } catch { lastError = error; if valid.isEmpty, start > now { start = max(now, start.addingTimeInterval(-60 * 60)) } else { break } }
        }
        guard !valid.isEmpty else {
            throw (lastError as? PlannerError) == nil ? lastError : PlannerError.noArrival
        }
        var seen = Set<String>()
        let unique = valid.filter { seen.insert("\($0.leaveBy.timeIntervalSince1970)-\($0.arriveAt.timeIntervalSince1970)").inserted }
        return Array(unique.sorted { $0.leaveBy > $1.leaveBy }.prefix(Self.maxItineraries))
    }

    /// Turns a route plan into timed legs using real scheduled departures.
    private func resolve(_ plan: RoutePlan, from a: PlanPoint, to b: PlanPoint, fromMode: AccessMode, toMode: AccessMode, departAt: Date) async throws -> Itinerary {
        guard let board = network.stations[plan.boardStation], let alight = network.stations[plan.alightStation] else { throw PlannerError.noRoute }
        var legs: [ItineraryLeg] = []

        let toStation = await accessLeg(fromMode, a.coordinate, .init(latitude: board.lat, longitude: board.lon))
        var t = departAt.addingTimeInterval(toStation.seconds)
        let firstAccess = (start: departAt, end: t)
        var firstBoard: Date?

        for leg in plan.legs {
            switch leg {
            case .transfer(let f, let to, let secs):
                guard let fs = network.stations[f], let ts = network.stations[to] else { continue }
                legs.append(ItineraryLeg(kind: .transfer, routeId: nil, directionId: nil, fromName: fs.name, toName: ts.name,
                                         start: t, end: t.addingTimeInterval(secs), stopCount: 0,
                                         coordinates: [.init(latitude: fs.lat, longitude: fs.lon), .init(latitude: ts.lat, longitude: ts.lon)]))
                t = t.addingTimeInterval(secs)
            case .transit(let tl):
                guard let from = tl.stationIds.first, let to = tl.stationIds.last,
                      let fs = network.stations[from], let ts = network.stations[to] else { continue }
                let trip = try await nextTrip(tl, from: from, to: to, notBefore: t)
                let (tripDepart, tripArrive) = (trip.depart, trip.arrive)
                firstBoard = firstBoard ?? tripDepart
                legs.append(ItineraryLeg(kind: .transit, routeId: tl.routeId, directionId: tl.directionId, fromName: fs.name, toName: ts.name,
                                         start: tripDepart, end: tripArrive, stopCount: tl.stationIds.count - 1,
                                         coordinates: tl.stationIds.compactMap { network.stations[$0] }.map { .init(latitude: $0.lat, longitude: $0.lon) },
                                         isLive: trip.isLive, delaySeconds: trip.delay,
                                         tripId: trip.tripId,
                                         tripStops: tl.stationIds.compactMap { network.stations[$0] }.map {
                                             TripStop(stationId: $0.id, name: $0.name, lat: $0.lat, lon: $0.lon)
                                         }))
                t = tripArrive
            }
        }
        guard let firstBoard else { throw PlannerError.noService }

        let fromStation = await accessLeg(toMode, .init(latitude: alight.lat, longitude: alight.lon), b.coordinate)
        let arrive = t.addingTimeInterval(fromStation.seconds)

        // Leave as late as possible: the access leg ends exactly when the first train departs.
        let leaveBy = max(departAt, firstBoard.addingTimeInterval(-toStation.seconds))
        let accessIn = ItineraryLeg(kind: .access(fromMode), routeId: nil, directionId: nil, fromName: a.name, toName: board.name,
                                    start: leaveBy, end: leaveBy.addingTimeInterval(toStation.seconds), stopCount: 0,
                                    coordinates: [a.coordinate, .init(latitude: board.lat, longitude: board.lon)])
        _ = firstAccess
        let accessOut = ItineraryLeg(kind: .access(toMode), routeId: nil, directionId: nil, fromName: alight.name, toName: b.name,
                                     start: t, end: arrive, stopCount: 0,
                                     coordinates: [.init(latitude: alight.lat, longitude: alight.lon), b.coordinate])
        return Itinerary(legs: [accessIn] + legs + [accessOut], leaveBy: leaveBy, arriveAt: arrive)
    }

    struct TimedTrip { let tripId: String; let depart: Date; let arrive: Date; var isLive = false; var delay = 0 }

    /// First trip on this leg's route that leaves at or after `notBefore` and calls at the alighting station.
    /// Scheduled times are replaced by live MBTA predictions where they exist, and cancelled or skipped trips are passed over.
    private func nextTrip(_ leg: TransitLeg, from: String, to: String, notBefore: Date) async throws -> TimedTrip {
        // Look a little earlier so a trip running late that is still catchable is not missed.
        let lookback = notBefore.addingTimeInterval(-600)
        let deps = try await provider.departures(routeId: leg.routeId, directionId: leg.directionId, stationId: from, after: lookback, limit: 14)
        var candidates: [TimedTrip] = []
        var tries = 0
        for d in deps {
            if let pid = d.patternId, let p = network.patterns.first(where: { $0.id == pid }) {
                let ids = p.stops.map(\.stationId)
                guard let i = ids.firstIndex(of: from), let j = ids.lastIndex(of: to), i < j else { continue }
            }
            let live = try? await provider.liveTimes(tripId: d.tripId, from: from, to: to)
            if live?.cancelled == true { continue }
            let depart = live?.depart ?? d.time
            guard depart >= notBefore else { continue }
            tries += 1
            if tries > 5 { break }
            var arrive = live?.arrive
            let usedLive = live?.depart != nil || arrive != nil
            if arrive == nil {
                guard let scheduled = try await provider.stopTime(tripId: d.tripId, stationId: to, on: d.time) else { continue }
                // A late trip is assumed to stay as late at the end as at the start.
                arrive = scheduled.addingTimeInterval(depart.timeIntervalSince(d.time))
            }
            guard let arrive, arrive > depart else { continue }
            candidates.append(TimedTrip(tripId: d.tripId, depart: depart, arrive: arrive, isLive: usedLive, delay: Int(depart.timeIntervalSince(d.time))))
            if candidates.count == 2 { break }
        }
        // A delayed trip can be overtaken by the next one, so take the earliest arrival.
        guard let best = candidates.min(by: { $0.arrive < $1.arrive }) else { throw PlannerError.noService }
        return best
    }
}
