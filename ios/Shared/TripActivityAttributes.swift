import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var nextStop: String
        var routeName: String
        var destination: String
        var stopsRemaining: Int
        var status: String
        var lastUpdated: Date
    }

    var origin: String
    var routeName: String
}
