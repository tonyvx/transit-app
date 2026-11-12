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

    func testTopModeSetsBothLegsAndAllowsOverrides() {
        let planner = AppModel().planner
        planner.setModeForBoth(.bike)
        XCTAssertEqual(planner.fromMode, .bike)
        XCTAssertEqual(planner.toMode, .bike)
        planner.toMode = .walk
        XCTAssertEqual(planner.fromMode, .bike)
        XCTAssertEqual(planner.toMode, .walk)
    }

    func testResolvingBothLocationsAutomaticallyPlansTrip() async throws {
        let a = NetStation(id: "A", name: "A", lat: 42.30, lon: -71.10)
        let b = NetStation(id: "B", name: "B", lat: 42.31, lon: -71.10)
        let network = TransitNetwork(stations: ["A": a, "B": b],
            patterns: [NetPattern(id: "P", routeId: "Red", directionId: 0,
                stops: [PatternStop(stationId: "A", offset: 0), PatternStop(stationId: "B", offset: 600)])])
        let provider = FakeProvider(deps: [("T1", 300)], arrive: ["T1": 900], live: [:],
                                    networkData: network, base: Date().addingTimeInterval(3600))
        let planner = PlannerModel(provider: provider, location: LocationTracker(),
            searchLocation: { text in
                let station = text == "start" ? a : b
                return PlanPoint(name: station.name, lat: station.lat, lon: station.lon)
            }, accessLeg: { _, _, _ in (60, 80) })
        planner.updateText("start", field: .from)
        await planner.search(.from)
        XCTAssertTrue(planner.results.isEmpty)
        planner.updateText("destination", field: .to)
        await planner.search(.to)
        for _ in 0..<100 where planner.results.isEmpty && planner.error == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(planner.error)
        XCTAssertEqual(planner.results.count, 1)
        XCTAssertEqual(planner.results.first?.legs.count, 3)
    }

    func testEditedLocationDiscardsLateSearchResult() async {
        var continuation: CheckedContinuation<PlanPoint?, Never>?
        let provider = FakeProvider(deps: [], arrive: [:], live: [:])
        let planner = PlannerModel(provider: provider, location: LocationTracker(),
            searchLocation: { _ in
                await withCheckedContinuation { continuation = $0 }
            })
        planner.updateText("old", field: .from)
        let search = Task { await planner.search(.from) }
        while continuation == nil { await Task.yield() }
        planner.updateText("new", field: .from)
        continuation?.resume(returning: PlanPoint(name: "old result", lat: 42, lon: -71))
        await search.value
        XCTAssertEqual(planner.fromText, "new")
        XCTAssertNil(planner.from)
        XCTAssertNil(planner.error)
    }

    func testFailedLookupRemainsVisibleWhenOtherLocationResolves() async {
        let planner = PlannerModel(provider: FakeProvider(deps: [], arrive: [:], live: [:]),
            location: LocationTracker(),
            searchLocation: { text in
                text == "missing" ? nil : PlanPoint(name: text, lat: 42, lon: -71)
            })
        planner.updateText("missing", field: .from)
        planner.updateText("found", field: .to)
        await planner.search(.from)
        await planner.search(.to)
        XCTAssertEqual(planner.locationErrors[.from], "No match for missing.")
        XCTAssertNil(planner.locationErrors[.to])
        XCTAssertNil(planner.from)
        XCTAssertEqual(planner.to?.name, "found")
    }
}
