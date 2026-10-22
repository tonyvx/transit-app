import Observation
import WidgetKit

@MainActor
@Observable
final class FavoritesModel {
    private(set) var stations: [FavoriteStation] = SharedStorage.stations()
    private(set) var trips: [SavedTrip] = SharedStorage.trips()

    func isFavorite(_ stopId: String) -> Bool { stations.contains { $0.stopId == stopId } }

    func toggleStation(stopId: String, name: String) {
        if let i = stations.firstIndex(where: { $0.stopId == stopId }) {
            stations.remove(at: i)
        } else {
            stations.append(FavoriteStation(stopId: stopId, name: name))
        }
        SharedStorage.saveStations(stations)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func removeStations(at offsets: IndexSet) {
        stations.remove(atOffsets: offsets)
        SharedStorage.saveStations(stations)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func moveStation(from: IndexSet, to: Int) {
        stations.move(fromOffsets: from, toOffset: to)
        SharedStorage.saveStations(stations)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func save(_ trip: SavedTrip) {
        if let i = trips.firstIndex(where: { $0.id == trip.id }) { trips[i] = trip } else { trips.append(trip) }
        SharedStorage.saveTrips(trips)
    }

    func remove(_ trip: SavedTrip) {
        Notifier.cancelCommuteReminder(trip)
        trips.removeAll { $0.id == trip.id }
        SharedStorage.saveTrips(trips)
    }

    func setReminder(_ trip: SavedTrip, minutes: Int?) async -> Bool {
        var t = trip
        t.reminderMinutes = minutes
        if minutes == nil {
            Notifier.cancelCommuteReminder(t)
        } else if await !Notifier.scheduleCommuteReminder(t) {
            return false
        }
        save(t)
        return true
    }
}
