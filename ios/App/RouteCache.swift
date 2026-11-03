import Foundation

/// Route shapes, names and terminals change a few times a year, so they are kept on disk instead of re-downloaded each launch.
struct RouteSnapshot: Codable, Sendable {
    var savedAt: Date
    var routes: [RouteInfo]
    var traces: [RouteTrace]
    var directions: [RouteDirection]
}

enum RouteCache {
    static let maxAge: TimeInterval = 7 * 24 * 3600

    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("route-snapshot.json")
    }

    static func load(now: Date = Date(), from url: URL = RouteCache.url) -> RouteSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(RouteSnapshot.self, from: data),
              now.timeIntervalSince(snapshot.savedAt) < maxAge,
              !snapshot.traces.isEmpty, !snapshot.routes.isEmpty else { return nil }
        return snapshot
    }

    static func save(_ snapshot: RouteSnapshot, to url: URL = RouteCache.url) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
