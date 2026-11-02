import Foundation

struct MapCoordinate: Sendable {
    let latitude: Double
    let longitude: Double
}

struct RouteTrace: Identifiable, Sendable {
    let id: String
    let routeId: String
    let line: LineGroup
    let coordinates: [MapCoordinate]
}

struct RouteDirection: Identifiable, Sendable {
    let routeId: String
    let direction: Direction
    let startStop: String
    let endStop: String
    var id: String { "\(routeId):\(direction.rawValue):\(startStop):\(endStop)" }
}

enum EncodedPolyline {
    static func decode(_ encoded: String) -> [MapCoordinate]? {
        let bytes = Array(encoded.utf8)
        var index = 0
        var latitude = 0
        var longitude = 0
        var coordinates: [MapCoordinate] = []

        func nextDelta() -> Int? {
            var result = 0
            var shift = 0
            while index < bytes.count, shift < 35 {
                let byte = Int(bytes[index]) - 63
                index += 1
                guard (0...63).contains(byte) else { return nil }
                result |= (byte & 0x1f) << shift
                shift += 5
                if byte < 0x20 {
                    return result & 1 == 1 ? ~(result >> 1) : result >> 1
                }
            }
            return nil
        }

        while index < bytes.count {
            guard let latDelta = nextDelta(), let lonDelta = nextDelta() else { return nil }
            latitude += latDelta
            longitude += lonDelta
            coordinates.append(MapCoordinate(
                latitude: Double(latitude) / 100_000,
                longitude: Double(longitude) / 100_000
            ))
        }
        return coordinates.count >= 2 ? coordinates : nil
    }
}

struct Vehicle: Identifiable, Sendable {
    let id: String
    let routeId: String
    let tripId: String?
    let directionId: Int?
    /// Branch id such as "Red-3", derived from the trip's route pattern; nil when unknown.
    let branchId: String?
    let label: String?
    let lat: Double
    let lon: Double
    let bearing: Double?
    let speedMps: Double?
    let status: String?
    let updatedAt: Date?
}

struct TransitAlert: Identifiable, Sendable {
    let id: String
    let effect: String
    let header: String
    let routeIds: [String]
    /// MBTA direction ids the alert applies to; empty means both directions.
    var directionIds: Set<Int> = []
}

struct RouteInfo: Identifiable, Sendable {
    let id: String
    let name: String
    let color: String?
}

/// A branch of a route that has several canonical patterns, e.g. the Red Line's Braintree and Ashmont branches.
struct Branch: Identifiable, Sendable {
    let id: String
    let routeId: String
    let name: String
}

struct Station: Identifiable, Hashable, Sendable {
    /// Stop id plus line group, so a shared station (e.g. Park Street) can appear once per line.
    var id: String { "\(stopId)|\(line.rawValue)" }
    let stopId: String
    let name: String
    let lat: Double
    let lon: Double
    let line: LineGroup
}

struct Arrival: Identifiable, Sendable {
    let id: String
    let routeId: String
    let vehicleId: String?
    let time: Date
    let isDeparture: Bool
}

struct TrainMatch: Sendable {
    let vehicleId: String
    let confidence: Double
    let pings: Int
}

struct Ping: Sendable {
    let lat: Double
    let lon: Double
    let accuracyM: Double
    let speedMps: Double?
    let heading: Double?
    let timestamp: Date
}

enum Confidence {
    case high, medium, low

    init(_ value: Double) {
        self = value >= 0.8 ? .high : value >= 0.6 ? .medium : .low
    }

    var label: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

enum LineGroup: String, CaseIterable, Identifiable, Sendable {
    case commuter = "Commuter", red = "Red", green = "Green", blue = "Blue", orange = "Orange", silver = "Silver"
    var id: String { rawValue }

    init?(routeId: String) {
        switch routeId {
        case "Red", "Mattapan": self = .red
        case "Orange": self = .orange
        case "Blue": self = .blue
        case _ where routeId.hasPrefix("Green"): self = .green
        case _ where routeId.hasPrefix("CR-"): self = .commuter
        case "741", "742", "743", "746", "749", "751": self = .silver
        default: return nil
        }
    }
}

/// MBTA direction_id 0 is outbound and 1 is inbound for commuter rail and Silver Line; subway lines use the same ids for their opposite compass directions.
enum Direction: Int, CaseIterable, Identifiable, Sendable {
    case outbound = 0, inbound = 1
    var id: Int { rawValue }
    var label: String { self == .inbound ? "Inbound" : "Outbound" }
}

/// Personal defaults for the legend filters. Empty by default, so every filter starts off.
struct Preferences: Equatable, Sendable {
    var lines: Set<LineGroup> = []
    var directions: Set<Direction> = []
    /// Route ids to restrict to. A line with none of its routes selected shows all of its routes.
    var routes: Set<String> = []
    /// Hide trains that have already passed the rider's location.
    var onlyApproaching = true

    private static let routesKey = "pref.routes"
    private static let approachingKey = "pref.onlyApproaching"
    private static let linesKey = "pref.lines"
    private static let directionsKey = "pref.directions"

    static func load() -> Preferences {
        let d = UserDefaults.standard
        return Preferences(
            lines: Set((d.stringArray(forKey: linesKey) ?? []).compactMap(LineGroup.init(rawValue:))),
            directions: Set((d.array(forKey: directionsKey) as? [Int] ?? []).compactMap(Direction.init(rawValue:))),
            routes: Set(d.stringArray(forKey: routesKey) ?? []),
            onlyApproaching: d.object(forKey: approachingKey) as? Bool ?? true)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(lines.map(\.rawValue), forKey: Self.linesKey)
        d.set(directions.map(\.rawValue), forKey: Self.directionsKey)
        d.set(Array(routes), forKey: Self.routesKey)
        d.set(onlyApproaching, forKey: Self.approachingKey)
    }
}

/// A line outside the rider's preferences whose first stop (in the selected direction) lies ahead of them.
struct NearbyStart: Sendable {
    let routeId: String
    let stationName: String
    let direction: Direction
    /// Driving time from the rider's location to the station; nil if it could not be estimated.
    let driveSeconds: TimeInterval?
}
