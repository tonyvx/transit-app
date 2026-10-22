import Foundation

struct FavoriteStation: Codable, Identifiable, Hashable, Sendable {
    let stopId: String
    let name: String
    var id: String { stopId }
}

struct SavedTrip: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var fromName: String
    var fromLat: Double
    var fromLon: Double
    var fromIsCurrentLocation: Bool
    var toName: String
    var toLat: Double
    var toLon: Double
    var toIsCurrentLocation: Bool
    var fromMode: String
    var toMode: String
    /// Weekday reminder time as minutes after midnight. Nil means no reminder.
    var reminderMinutes: Int?
}

/// Favorites live in an App Group so the widget can read them. If the group is unavailable, the app still works from its own defaults.
enum SharedStorage {
    static let groupId = "group.com.tonyvx.transitapp"
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: groupId) ?? .standard

    private static let stationsKey = "favorites.stations"
    private static let tripsKey = "favorites.trips"

    static func stations() -> [FavoriteStation] { load(stationsKey) }
    static func saveStations(_ v: [FavoriteStation]) { save(v, stationsKey) }
    static func trips() -> [SavedTrip] { load(tripsKey) }
    static func saveTrips(_ v: [SavedTrip]) { save(v, tripsKey) }

    private static func load<T: Decodable>(_ key: String) -> [T] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([T].self, from: $0) } ?? []
    }

    private static func save<T: Encodable>(_ v: [T], _ key: String) {
        if let d = try? JSONEncoder().encode(v) { defaults.set(d, forKey: key) }
    }
}
