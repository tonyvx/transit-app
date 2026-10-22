import Foundation

struct TransitLeg: Sendable {
    let routeId: String
    let directionId: Int
    let patternId: String
    let stationIds: [String]
    let rideSeconds: TimeInterval
}

enum PlanLeg: Sendable {
    case transit(TransitLeg)
    case transfer(from: String, to: String, seconds: TimeInterval)
}

struct RoutePlan: Sendable {
    let boardStation: String
    let alightStation: String
    /// Estimated total seconds including access and egress.
    let cost: TimeInterval
    let legs: [PlanLeg]

    var signature: String {
        legs.map {
            switch $0 {
            case .transit(let t): "\(t.patternId):\(t.stationIds.first ?? ""):\(t.stationIds.last ?? "")"
            case .transfer(let f, let t, _): "w:\(f):\(t)"
            }
        }.joined(separator: ">")
    }
}

/// Shortest-path search over stations and route patterns, with walking transfers between nearby stations.
struct Router: Sendable {
    private enum Kind: UInt8 { case board, ride, alight, walk }
    private struct Edge { let to: Int; let cost: Double; let kind: Kind }

    private let network: TransitNetwork
    private let stationIds: [String]
    private let stationIndex: [String: Int]
    private var edges: [[Edge]]
    private var nodePattern: [Int]
    private var nodeStop: [Int]

    static let walkTransferMaxM = 300.0

    /// Average wait for a train plus a penalty that discourages extra transfers.
    private static func boardCost(routeId: String) -> Double {
        let wait: Double = routeId.hasPrefix("CR-") ? 900 : (Int(routeId) != nil ? 420 : 240)
        return wait + 120
    }

    init(network: TransitNetwork) {
        self.network = network
        let ids = network.stations.keys.sorted()
        stationIds = ids
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        stationIndex = index
        var edges = [[Edge]](repeating: [], count: ids.count)
        var nodePattern = [Int](repeating: -1, count: ids.count)
        var nodeStop = [Int](repeating: -1, count: ids.count)

        for (pi, p) in network.patterns.enumerated() {
            let stops = p.stops.filter { index[$0.stationId] != nil }
            guard stops.count > 1 else { continue }
            let base = edges.count
            for j in stops.indices {
                edges.append([])
                nodePattern.append(pi)
                nodeStop.append(j)
            }
            for j in stops.indices {
                let node = base + j
                let st = index[stops[j].stationId]!
                edges[node].append(Edge(to: st, cost: 0, kind: .alight))
                if j < stops.count - 1 {
                    edges[st].append(Edge(to: node, cost: Self.boardCost(routeId: p.routeId), kind: .board))
                    edges[node].append(Edge(to: node + 1, cost: max(1, stops[j + 1].offset - stops[j].offset), kind: .ride))
                }
            }
        }

        for i in ids.indices {
            for k in (i + 1)..<max(i + 1, ids.count) {
                let a = network.stations[ids[i]]!, b = network.stations[ids[k]]!
                let d = Geo.distanceM(a.lat, a.lon, b.lat, b.lon)
                guard d <= Self.walkTransferMaxM else { continue }
                let secs = d * AccessMode.circuity / AccessMode.walk.speedMps + 60
                edges[i].append(Edge(to: k, cost: secs, kind: .walk))
                edges[k].append(Edge(to: i, cost: secs, kind: .walk))
            }
        }
        self.edges = edges
        self.nodePattern = nodePattern
        self.nodeStop = nodeStop
    }

    /// Stations ordered by straight-line distance from a coordinate.
    func nearestStations(lat: Double, lon: Double) -> [(station: NetStation, distanceM: Double)] {
        network.stations.values
            .map { ($0, Geo.distanceM(lat, lon, $0.lat, $0.lon)) }
            .sorted { $0.1 < $1.1 }
    }

    /// Best plan from one station to any of the targets (station id to egress seconds). Needs at least one train ride.
    func plan(from source: String, startCost: Double, targets: [String: Double]) -> RoutePlan? {
        guard let src = stationIndex[source] else { return nil }
        let n = edges.count
        var dist = [Double](repeating: .infinity, count: n)
        var prev = [Int](repeating: -1, count: n)
        var prevEdge = [(kind: Kind, cost: Double)](repeating: (.walk, 0), count: n)
        var heap = MinHeap()
        dist[src] = startCost
        heap.push(startCost, src)

        while let (d, u) = heap.pop() {
            if d > dist[u] { continue }
            for e in edges[u] {
                let nd = d + e.cost
                if nd < dist[e.to] {
                    dist[e.to] = nd
                    prev[e.to] = u
                    prevEdge[e.to] = (e.kind, e.cost)
                    heap.push(nd, e.to)
                }
            }
        }

        let ranked = targets.compactMap { id, egress -> (String, Double)? in
            guard let i = stationIndex[id], dist[i].isFinite, id != source else { return nil }
            return (id, dist[i] + egress)
        }.sorted { $0.1 < $1.1 }

        for (target, total) in ranked {
            var path = [stationIndex[target]!]
            while let p = prev[path.last!] as Int?, p >= 0 { path.append(p) }
            path.reverse()
            let legs = buildLegs(path: path, prevEdge: prevEdge)
            if legs.contains(where: { if case .transit = $0 { true } else { false } }) {
                return RoutePlan(boardStation: firstBoardStation(legs) ?? source, alightStation: target, cost: total, legs: legs)
            }
        }
        return nil
    }

    private func firstBoardStation(_ legs: [PlanLeg]) -> String? {
        for l in legs { if case .transit(let t) = l { return t.stationIds.first } }
        return nil
    }

    private func buildLegs(path: [Int], prevEdge: [(kind: Kind, cost: Double)]) -> [PlanLeg] {
        var legs: [PlanLeg] = []
        var pattern = -1
        var stations: [String] = []
        var secs = 0.0

        func stationId(_ node: Int) -> String {
            if node < stationIds.count { return stationIds[node] }
            return network.patterns[nodePattern[node]].stops.filter { stationIndex[$0.stationId] != nil }[nodeStop[node]].stationId
        }

        for i in 1..<max(1, path.count) {
            let u = path[i - 1], v = path[i]
            let e = prevEdge[v]
            switch e.kind {
            case .board:
                pattern = nodePattern[v]
                stations = [stationId(u)]
                secs = 0
            case .ride:
                stations.append(stationId(v))
                secs += e.cost
            case .alight:
                let p = network.patterns[pattern]
                legs.append(.transit(TransitLeg(routeId: p.routeId, directionId: p.directionId, patternId: p.id, stationIds: stations, rideSeconds: secs)))
            case .walk:
                legs.append(.transfer(from: stationId(u), to: stationId(v), seconds: e.cost))
            }
        }
        return legs
    }
}

enum Geo {
    static func distanceM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

private struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ cost: Double, _ node: Int) {
        items.append((cost, node))
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if items[p].0 <= items[i].0 { break }
            items.swapAt(p, i)
            i = p
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l].0 < items[m].0 { m = l }
                if r < items.count, items[r].0 < items[m].0 { m = r }
                if m == i { break }
                items.swapAt(m, i)
                i = m
            }
        }
        return first
    }
}
