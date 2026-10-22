import CoreLocation
import Foundation

enum AccessMode: String, CaseIterable, Identifiable, Sendable {
    case walk, bike, scooter, car
    var id: String { rawValue }

    var label: String {
        switch self {
        case .walk: "Walk"
        case .bike: "Bike"
        case .scooter: "Scooter"
        case .car: "Car"
        }
    }

    var icon: String {
        switch self {
        case .walk: "figure.walk"
        case .bike: "bicycle"
        case .scooter: "scooter"
        case .car: "car.fill"
        }
    }

    var speedMps: Double {
        switch self {
        case .walk: 1.35
        case .bike: 4.2
        case .scooter: 4.5
        case .car: 8
        }
    }

    /// Time to park the car or lock up the bike or scooter.
    var overheadSeconds: Double {
        switch self {
        case .walk: 0
        case .bike, .scooter: 60
        case .car: 240
        }
    }

    var maxDistanceM: Double {
        switch self {
        case .walk: 2_500
        case .bike, .scooter: 6_000
        case .car: 25_000
        }
    }

    /// Street routes are longer than straight lines.
    static let circuity = 1.35

    func estimate(distanceM: Double) -> TimeInterval {
        distanceM * Self.circuity / speedMps + overheadSeconds
    }
}

struct PlanPoint: Equatable, Sendable {
    var name: String
    var lat: Double
    var lon: Double
    var isCurrentLocation = false

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

struct NetStation: Identifiable, Sendable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
}

struct PatternStop: Sendable {
    let stationId: String
    /// Seconds after the first stop of the pattern's representative trip.
    let offset: TimeInterval
}

struct NetPattern: Identifiable, Sendable {
    let id: String
    let routeId: String
    let directionId: Int
    let stops: [PatternStop]
}

struct TransitNetwork: Sendable {
    let stations: [String: NetStation]
    let patterns: [NetPattern]
}

struct ScheduledDeparture: Sendable {
    let tripId: String
    let patternId: String?
    let time: Date
}

/// Real-time times for one trip between two stations. Nil times mean the MBTA has no prediction for that stop.
struct LiveTimes: Sendable {
    var depart: Date?
    var arrive: Date?
    var cancelled = false
}

struct ItineraryLeg: Identifiable {
    enum Kind {
        case access(AccessMode)
        case transfer
        case transit
    }

    let id = UUID()
    let kind: Kind
    let routeId: String?
    let directionId: Int?
    let fromName: String
    let toName: String
    let start: Date
    let end: Date
    let stopCount: Int
    let coordinates: [CLLocationCoordinate2D]
    /// True when `start` or `end` comes from a live MBTA prediction instead of the timetable.
    var isLive = false
    /// Live departure minus scheduled departure.
    var delaySeconds = 0
}

struct Itinerary: Identifiable {
    let id = UUID()
    let legs: [ItineraryLeg]
    /// Latest time to set off from point A and still make the first train.
    let leaveBy: Date
    let arriveAt: Date

    var duration: TimeInterval { arriveAt.timeIntervalSince(leaveBy) }
    var transitLegs: [ItineraryLeg] { legs.filter { if case .transit = $0.kind { true } else { false } } }
    var isLive: Bool { transitLegs.contains { $0.isLive } }
    var transfers: Int { max(0, transitLegs.count - 1) }
}

enum PlannerError: LocalizedError {
    case noStationsNear(String)
    case noRoute
    case noService
    case noArrival
    case network

    var errorDescription: String? {
        switch self {
        case .noStationsNear(let what): "No stations within reach of \(what) with that mode."
        case .noRoute: "No route found between those stations."
        case .noService: "No scheduled service found for that time."
        case .noArrival: "No trip gets you there by that time."
        case .network: "Couldn't load MBTA data."
        }
    }
}
