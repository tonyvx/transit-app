import XCTest
@testable import TransitApp

@MainActor
final class FavoritesTests: XCTestCase {
    override func setUp() async throws {
        SharedStorage.saveStations([])
        SharedStorage.saveTrips([])
    }

    func testToggleStationPersists() {
        let f = FavoritesModel()
        f.toggleStation(stopId: "place-pktrm", name: "Park Street")
        XCTAssertTrue(f.isFavorite("place-pktrm"))
        XCTAssertEqual(SharedStorage.stations().map(\.stopId), ["place-pktrm"])
        f.toggleStation(stopId: "place-pktrm", name: "Park Street")
        XCTAssertFalse(f.isFavorite("place-pktrm"))
        XCTAssertTrue(SharedStorage.stations().isEmpty)
    }

    func testStationOrderIsKept() {
        let f = FavoritesModel()
        f.toggleStation(stopId: "a", name: "A")
        f.toggleStation(stopId: "b", name: "B")
        f.moveStation(from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(SharedStorage.stations().map(\.stopId), ["b", "a"])
    }

    func testSavedTripRoundTrip() {
        let f = FavoritesModel()
        let t = SavedTrip(name: "Home → Work", fromName: "Home", fromLat: 42.3, fromLon: -71.1, fromIsCurrentLocation: true,
                          toName: "Work", toLat: 42.4, toLon: -71.0, toIsCurrentLocation: false, fromMode: "bike", toMode: "walk")
        f.save(t)
        XCTAssertEqual(SharedStorage.trips(), [t])
        var edited = t
        edited.name = "Commute"
        f.save(edited)
        XCTAssertEqual(SharedStorage.trips().map(\.name), ["Commute"])
        f.remove(t)
        XCTAssertTrue(SharedStorage.trips().isEmpty)
    }

    func testLoadingSavedTripFillsPlanner() {
        let model = AppModel()
        let t = SavedTrip(name: "x", fromName: "Home", fromLat: 42.3, fromLon: -71.1, fromIsCurrentLocation: false,
                          toName: "Work", toLat: 42.4, toLon: -71.0, toIsCurrentLocation: false, fromMode: "bike", toMode: "car")
        model.planner.load(t)
        XCTAssertEqual(model.planner.from?.name, "Home")
        XCTAssertEqual(model.planner.fromMode, .bike)
        XCTAssertEqual(model.planner.toMode, .car)
        XCTAssertEqual(model.planner.savedTrip()?.toName, "Work")
    }
}
