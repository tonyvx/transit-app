import Foundation

/// Direct MBTA V3 client. Keep this behind a protocol if other cities are added later.
protocol TransitProvider: Sendable {
    func vehicles() async throws -> [Vehicle]
    func alerts() async throws -> [TransitAlert]
    func routes() async throws -> [RouteInfo]
    func branches() async throws -> [Branch]
    func stations(routeIds: [String]) async throws -> [StopInfo]
    /// First stops of a route's trips in one direction.
    func origins(routeId: String, directionId: Int) async throws -> [StopInfo]
    /// Every rail and Silver Line stop pattern with travel times, for trip planning.
    func network() async throws -> TransitNetwork
    /// Scheduled departures from a station for a route and direction, at or after a time.
    func departures(routeId: String, directionId: Int, stationId: String, after: Date, limit: Int) async throws -> [ScheduledDeparture]
    /// Scheduled time a trip reaches a station.
    func stopTime(tripId: String, stationId: String, on day: Date) async throws -> Date?
    /// Live predicted times for a trip at its boarding and alighting stations.
    func liveTimes(tripId: String, from: String, to: String) async throws -> LiveTimes?
    func arrivals(stopId: String, routeIds: [String]) async throws -> [Arrival]
}

struct StopInfo: Sendable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
}

struct MBTAClient: TransitProvider {
    private let apiKey: String

    init(apiKey: String = Bundle.main.object(forInfoDictionaryKey: "MBTA_API_KEY") as? String ?? "") {
        self.apiKey = apiKey
    }

    private static let mph: Double = 0.44704
    /// Rail types: 0 light rail (Green, Mattapan), 1 subway (Red, Orange, Blue), 2 commuter rail.
    private static let railTypes = "0,1,2"
    /// Silver Line is classified as bus by the MBTA, so it is selected by route id.
    private static let silverLine = "741,742,743,746,749,751"

    private struct Ref: Decodable { let id: String }
    private struct Rel: Decodable { let data: Ref? }
    private struct Rels: Decodable { let route: Rel?; let trip: Rel?; let route_pattern: Rel?; let vehicle: Rel?; let stop: Rel?; let parent_station: Rel? }
    private struct Res<A: Decodable>: Decodable { let id: String; let attributes: A; let relationships: Rels? }
    private struct Doc<A: Decodable>: Decodable { let data: [Res<A>] }
    private struct Empty: Decodable {}
    private struct VehicleDoc: Decodable { let data: [Res<VehicleAttrs>]; let included: [Res<Empty>]? }
    private struct StopAttrs: Decodable { let name: String; let latitude: Double?; let longitude: Double?; let location_type: Int? }
    private struct ScheduleDoc: Decodable { let data: [Res<Empty>]; let included: [Res<StopAttrs>]? }
    private struct SchedAttrs: Decodable { let arrival_time: String?; let departure_time: String?; let stop_sequence: Int? }
    private struct TripAttrs: Decodable { let direction_id: Int? }
    private struct StopParent: Decodable {}
    private struct PredDoc: Decodable { let data: [Res<PredictionAttrs>]; let included: [Res<StopParent>]? }
    private struct SchedDoc<I: Decodable>: Decodable { let data: [Res<SchedAttrs>]; let included: [Res<I>]? }
    private struct PredictionAttrs: Decodable { let arrival_time: String?; let departure_time: String?; let schedule_relationship: String? }
    private struct PatternAttrs: Decodable { let name: String; let direction_id: Int }

    private struct VehicleAttrs: Decodable {
        let latitude: Double?, longitude: Double?, bearing: Double?, speed: Double?, direction_id: Int?
        let label: String?, current_status: String?, updated_at: String?
    }
    private struct AlertAttrs: Decodable {
        struct Entity: Decodable { let route: String? }
        let effect: String, header: String, informed_entity: [Entity]
    }
    private struct RouteAttrs: Decodable { let long_name: String; let color: String? }

    private func fetchData(_ path: String, _ query: [String: String]) async throws -> Data {
        var c = URLComponents(string: "https://api-v3.mbta.com\(path)")!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!)
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private func fetch<A: Decodable>(_ path: String, _ query: [String: String], as _: A.Type) async throws -> [Res<A>] {
        try JSONDecoder().decode(Doc<A>.self, from: try await fetchData(path, query)).data
    }

    /// "Red-3-1" -> "Red-3": a pattern id without its trailing direction.
    private static func branchId(fromPattern id: String) -> String {
        id.split(separator: "-", omittingEmptySubsequences: false).dropLast().joined(separator: "-")
    }

    /// Runs the same query for rail types and for the Silver Line, and merges the results.
    private func fetchLines<A: Decodable>(_ path: String, _ extra: [String: String] = [:], as t: A.Type) async throws -> [Res<A>] {
        async let rail = fetch(path, extra.merging(["filter[route_type]": Self.railTypes]) { $1 }, as: t)
        async let silver = fetch(path, extra.merging(["filter[route]": Self.silverLine]) { $1 }, as: t)
        let all = try await rail + silver
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted }
    }

    private func fetchVehicleDoc(_ query: [String: String]) async throws -> VehicleDoc {
        try JSONDecoder().decode(VehicleDoc.self, from: try await fetchData("/vehicles", query.merging(["include": "trip"]) { $1 }))
    }

    func vehicles() async throws -> [Vehicle] {
        let parse = ISO8601DateFormatter()
        async let rail = fetchVehicleDoc(["filter[route_type]": Self.railTypes])
        async let silver = fetchVehicleDoc(["filter[route]": Self.silverLine])
        let docs = try await [rail, silver]
        var patternByTrip: [String: String] = [:]
        for doc in docs {
            for t in doc.included ?? [] {
                if let p = t.relationships?.route_pattern?.data?.id { patternByTrip[t.id] = Self.branchId(fromPattern: p) }
            }
        }
        var seen = Set<String>()
        let all = docs.flatMap(\.data).filter { seen.insert($0.id).inserted }
        return all.compactMap { r in
            guard let lat = r.attributes.latitude, let lon = r.attributes.longitude else { return nil }
            return Vehicle(
                id: r.id, routeId: r.relationships?.route?.data?.id ?? "", tripId: r.relationships?.trip?.data?.id, directionId: r.attributes.direction_id,
                branchId: r.relationships?.trip?.data.flatMap { patternByTrip[$0.id] },
                label: r.attributes.label, lat: lat, lon: lon, bearing: r.attributes.bearing,
                speedMps: r.attributes.speed.map { $0 * Self.mph }, status: r.attributes.current_status,
                updatedAt: r.attributes.updated_at.flatMap { parse.date(from: $0) })
        }
    }

    func alerts() async throws -> [TransitAlert] {
        try await fetchLines("/alerts", ["filter[activity]": "BOARD,EXIT,RIDE"], as: AlertAttrs.self).map {
            TransitAlert(id: $0.id, effect: $0.attributes.effect, header: $0.attributes.header,
                         routeIds: Array(Set($0.attributes.informed_entity.compactMap(\.route))))
        }
    }

    func routes() async throws -> [RouteInfo] {
        async let rail = fetch("/routes", ["filter[type]": Self.railTypes], as: RouteAttrs.self)
        async let silver = fetch("/routes", ["filter[id]": Self.silverLine], as: RouteAttrs.self)
        return try await (rail + silver).map {
            RouteInfo(id: $0.id, name: $0.attributes.long_name, color: $0.attributes.color.map { "#\($0)" })
        }
    }

    /// Branches exist where a route has more than one canonical pattern per direction (the Red Line).
    func branches() async throws -> [Branch] {
        // route_patterns has no route_type filter, so look up the subway and light-rail route ids first.
        let routeIds = try await fetch("/routes", ["filter[type]": "0,1"], as: RouteAttrs.self).map(\.id).joined(separator: ",")
        let patterns = try await fetch("/route_patterns", ["filter[route]": routeIds, "filter[canonical]": "true", "filter[direction_id]": "0"], as: PatternAttrs.self)
        let byRoute = Dictionary(grouping: patterns) { $0.relationships?.route?.data?.id ?? "" }
        return byRoute.filter { $0.value.count > 1 }.flatMap { routeId, list in
            list.map { p in
                let end = p.attributes.name.components(separatedBy: " - ").last ?? p.attributes.name
                return Branch(id: Self.branchId(fromPattern: p.id), routeId: routeId, name: "\(end) branch")
            }
        }.sorted { $0.name < $1.name }
    }

    func stations(routeIds: [String]) async throws -> [StopInfo] {
        guard !routeIds.isEmpty else { return [] }
        let stops = try await fetch("/stops", ["filter[route]": routeIds.joined(separator: ","), "filter[location_type]": "0,1"], as: StopAttrs.self)
        // Keep stations, plus standalone stops (e.g. Silver Line airport terminals) that have no parent station.
        return stops.compactMap { r in
            guard let lat = r.attributes.latitude, let lon = r.attributes.longitude else { return nil }
            guard r.attributes.location_type == 1 || r.relationships?.parent_station?.data == nil else { return nil }
            return StopInfo(id: r.id, name: r.attributes.name, lat: lat, lon: lon)
        }
    }

    func origins(routeId: String, directionId: Int) async throws -> [StopInfo] {
        let data = try await fetchData("/schedules", [
            "filter[route]": routeId, "filter[direction_id]": String(directionId), "filter[stop_sequence]": "first",
            "include": "stop,stop.parent_station", "page[limit]": "300",
        ])
        let doc = try JSONDecoder().decode(ScheduleDoc.self, from: data)
        let byId = Dictionary(doc.included?.map { ($0.id, $0) } ?? [], uniquingKeysWith: { a, _ in a })
        var out: [String: StopInfo] = [:]
        for sched in doc.data {
            guard let stopId = sched.relationships?.stop?.data?.id, let stop = byId[stopId] else { continue }
            let station = stop.relationships?.parent_station?.data.flatMap { byId[$0.id] } ?? stop
            guard let lat = station.attributes.latitude, let lon = station.attributes.longitude else { continue }
            out[station.id] = StopInfo(id: station.id, name: station.attributes.name, lat: lat, lon: lon)
        }
        return Array(out.values)
    }

    func arrivals(stopId: String, routeIds: [String]) async throws -> [Arrival] {
        let parse = ISO8601DateFormatter()
        let preds = try await fetch("/predictions", ["filter[stop]": stopId, "filter[route]": routeIds.joined(separator: ","), "sort": "arrival_time"], as: PredictionAttrs.self)
        return preds.compactMap { p in
            let arr = p.attributes.arrival_time.flatMap { parse.date(from: $0) }
            let dep = p.attributes.departure_time.flatMap { parse.date(from: $0) }
            guard let time = arr ?? dep else { return nil }
            return Arrival(id: p.id, routeId: p.relationships?.route?.data?.id ?? "", vehicleId: p.relationships?.vehicle?.data?.id,
                           time: time, isDeparture: arr == nil)
        }.sorted { $0.time < $1.time }
    }

    func liveTimes(tripId: String, from: String, to: String) async throws -> LiveTimes? {
        let parse = ISO8601DateFormatter()
        let data = try await fetchData("/predictions", [
            "filter[trip]": tripId, "filter[stop]": "\(from),\(to)", "include": "stop", "fields[stop]": "parent_station",
        ])
        let doc = try JSONDecoder().decode(PredDoc.self, from: data)
        let stops = Dictionary(doc.included?.map { ($0.id, $0) } ?? [], uniquingKeysWith: { a, _ in a })
        // Predictions are per platform, so map each one up to its parent station.
        func stationId(_ p: Res<PredictionAttrs>) -> String? {
            guard let id = p.relationships?.stop?.data?.id else { return nil }
            return stops[id]?.relationships?.parent_station?.data?.id ?? id
        }
        guard !doc.data.isEmpty else { return nil }
        var out = LiveTimes()
        for p in doc.data {
            let sid = stationId(p)
            let skipped = p.attributes.schedule_relationship.map { $0 == "SKIPPED" || $0 == "CANCELLED" } ?? false
            if sid == from {
                if skipped { out.cancelled = true }
                out.depart = p.attributes.departure_time.flatMap { parse.date(from: $0) } ?? out.depart
            } else if sid == to {
                out.arrive = p.attributes.arrival_time.flatMap { parse.date(from: $0) } ?? p.attributes.departure_time.flatMap { parse.date(from: $0) } ?? out.arrive
            }
        }
        return out
    }

    func network() async throws -> TransitNetwork {
        let routeIds = Set(try await routes().map(\.id))
        // One trip per route pattern, taken from the first stops of all of today's trips.
        let firstData = try await fetchData("/schedules", [
            "filter[route]": routeIds.sorted().joined(separator: ","), "filter[stop_sequence]": "first", "include": "trip",
            "fields[schedule]": "trip", "fields[trip]": "route_pattern,route,direction_id", "page[limit]": "20000",
        ])
        let first = try JSONDecoder().decode(SchedDoc<TripAttrs>.self, from: firstData)
        var tripByPattern: [String: (trip: String, route: String, dir: Int)] = [:]
        for t in first.included ?? [] {
            guard let pid = t.relationships?.route_pattern?.data?.id, let rid = t.relationships?.route?.data?.id,
                  routeIds.contains(rid), tripByPattern[pid] == nil else { continue }
            tripByPattern[pid] = (t.id, rid, t.attributes.direction_id ?? 0)
        }
        guard !tripByPattern.isEmpty else { throw URLError(.cannotParseResponse) }

        let data = try await fetchData("/schedules", [
            "filter[trip]": tripByPattern.values.map(\.trip).joined(separator: ","), "include": "stop,stop.parent_station",
            "fields[schedule]": "arrival_time,departure_time,stop_sequence,trip,stop",
            "fields[stop]": "name,latitude,longitude,parent_station,location_type", "page[limit]": "20000",
        ])
        let doc = try JSONDecoder().decode(SchedDoc<StopAttrs>.self, from: data)
        let stopById = Dictionary(doc.included?.map { ($0.id, $0) } ?? [], uniquingKeysWith: { a, _ in a })
        let parse = ISO8601DateFormatter()
        let rowsByTrip = Dictionary(grouping: doc.data) { $0.relationships?.trip?.data?.id ?? "" }

        func station(_ stopId: String) -> NetStation? {
            guard let stop = stopById[stopId] else { return nil }
            let st = stop.relationships?.parent_station?.data.flatMap { stopById[$0.id] } ?? stop
            guard let lat = st.attributes.latitude, let lon = st.attributes.longitude else { return nil }
            return NetStation(id: st.id, name: st.attributes.name, lat: lat, lon: lon)
        }

        var stations: [String: NetStation] = [:]
        var patterns: [NetPattern] = []
        for (pid, info) in tripByPattern {
            let rows = (rowsByTrip[info.trip] ?? []).sorted { ($0.attributes.stop_sequence ?? 0) < ($1.attributes.stop_sequence ?? 0) }
            var stops: [PatternStop] = []
            var t0: Date?
            for r in rows {
                guard let stopId = r.relationships?.stop?.data?.id, let st = station(stopId),
                      let time = (r.attributes.departure_time ?? r.attributes.arrival_time).flatMap({ parse.date(from: $0) }) else { continue }
                t0 = t0 ?? time
                if stops.last?.stationId == st.id { continue }
                stations[st.id] = st
                stops.append(PatternStop(stationId: st.id, offset: time.timeIntervalSince(t0!)))
            }
            if stops.count > 1 { patterns.append(NetPattern(id: pid, routeId: info.route, directionId: info.dir, stops: stops)) }
        }
        return TransitNetwork(stations: stations, patterns: patterns.sorted { $0.id < $1.id })
    }

    private static let bostonZone = TimeZone(identifier: "America/New_York")!

    func departures(routeId: String, directionId: Int, stationId: String, after: Date, limit: Int) async throws -> [ScheduledDeparture] {
        let time = DateFormatter()
        time.timeZone = Self.bostonZone
        time.dateFormat = "HH:mm"
        let day = DateFormatter()
        day.timeZone = Self.bostonZone
        day.dateFormat = "yyyy-MM-dd"
        let data = try await fetchData("/schedules", [
            "filter[route]": routeId, "filter[direction_id]": String(directionId), "filter[stop]": stationId,
            "filter[date]": day.string(from: after), "filter[min_time]": time.string(from: after),
            "sort": "departure_time", "include": "trip", "fields[schedule]": "departure_time,trip",
            "fields[trip]": "route_pattern", "page[limit]": String(limit),
        ])
        let doc = try JSONDecoder().decode(SchedDoc<Empty>.self, from: data)
        let patternByTrip = Dictionary(doc.included?.map { ($0.id, $0.relationships?.route_pattern?.data?.id) } ?? [], uniquingKeysWith: { a, _ in a })
        let parse = ISO8601DateFormatter()
        return doc.data.compactMap { r in
            guard let tripId = r.relationships?.trip?.data?.id, let t = r.attributes.departure_time.flatMap({ parse.date(from: $0) }) else { return nil }
            return ScheduledDeparture(tripId: tripId, patternId: patternByTrip[tripId] ?? nil, time: t)
        }
    }

    func stopTime(tripId: String, stationId: String, on day: Date) async throws -> Date? {
        let fmt = DateFormatter()
        fmt.timeZone = Self.bostonZone
        fmt.dateFormat = "yyyy-MM-dd"
        // Without a date the MBTA returns the times for today, which breaks trips planned for another day.
        let data = try await fetchData("/schedules", [
            "filter[trip]": tripId, "filter[stop]": stationId, "filter[date]": fmt.string(from: day), "fields[schedule]": "arrival_time,departure_time",
        ])
        let doc = try JSONDecoder().decode(SchedDoc<Empty>.self, from: data)
        let parse = ISO8601DateFormatter()
        return doc.data.compactMap { ($0.attributes.arrival_time ?? $0.attributes.departure_time).flatMap { parse.date(from: $0) } }.first
    }
}
