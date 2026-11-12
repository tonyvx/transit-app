import XCTest
@testable import TransitApp

final class VehicleFilterTests: XCTestCase {
    func testTripMapVisibilityOnlyShowsTripStationsAndRoutesWhenEnabled() {
        let tripStation = Station(stopId: "A", name: "A", lat: 42, lon: -71, line: .red)
        let otherRedStation = Station(stopId: "B", name: "B", lat: 42, lon: -71, line: .red)
        let otherLineAtTripStation = Station(stopId: "A", name: "A", lat: 42, lon: -71, line: .orange)
        let all = TripMapVisibility(plannedRouteIDs: ["Red", "CR-Fitchburg"], plannedStationIDs: ["A"], hideOtherLines: false)
        XCTAssertTrue(all.showsRoute("Orange"))
        XCTAssertTrue(all.showsStation(otherRedStation))
        XCTAssertFalse(all.fadesRouteTraces)

        let tripOnly = TripMapVisibility(plannedRouteIDs: ["Red", "CR-Fitchburg"], plannedStationIDs: ["A"], hideOtherLines: true)
        XCTAssertTrue(tripOnly.showsRoute("Red"))
        XCTAssertTrue(tripOnly.showsRoute("CR-Fitchburg"))
        XCTAssertFalse(tripOnly.showsRoute("Orange"))
        XCTAssertFalse(tripOnly.showsRoute("CR-Lowell"))
        XCTAssertTrue(tripOnly.fadesRouteTraces)
        XCTAssertTrue(tripOnly.showsStation(tripStation))
        XCTAssertFalse(tripOnly.showsStation(otherRedStation))
        XCTAssertFalse(tripOnly.showsStation(otherLineAtTripStation))

        let noTrip = TripMapVisibility(plannedRouteIDs: [], plannedStationIDs: [], hideOtherLines: true)
        XCTAssertTrue(noTrip.showsRoute("Orange"))
        XCTAssertTrue(noTrip.showsStation(otherLineAtTripStation))
        XCTAssertFalse(noTrip.fadesRouteTraces)
    }

    func testTripRoutePathClipsShapeAndSupportsReverseTrips() throws {
        let trace = RouteTrace(id: "red", routeId: "Red", line: .red, coordinates: (0...4).map {
            MapCoordinate(latitude: 42 + Double($0) * 0.01, longitude: -71)
        })
        let stops = [
            TripStop(stationId: "a", name: "A", lat: 42.005, lon: -71),
            TripStop(stationId: "b", name: "B", lat: 42.02, lon: -71),
            TripStop(stationId: "c", name: "C", lat: 42.035, lon: -71),
        ]
        let forward = try XCTUnwrap(TripRoutePath.coordinates(stops: stops, traces: [trace]))
        XCTAssertEqual(forward.count, 5)
        XCTAssertEqual(forward.first!.latitude, 42.005, accuracy: 0.000001)
        XCTAssertEqual(forward.last!.latitude, 42.035, accuracy: 0.000001)
        let reverse = try XCTUnwrap(TripRoutePath.coordinates(stops: stops.reversed(), traces: [trace]))
        XCTAssertEqual(reverse.first!.latitude, 42.035, accuracy: 0.000001)
        XCTAssertEqual(reverse.last!.latitude, 42.005, accuracy: 0.000001)
    }

    func testTripRoutePathRejectsWrongBranchesAndNonMonotonicStops() {
        let trace = RouteTrace(id: "red", routeId: "Red", line: .red, coordinates: (0...4).map {
            MapCoordinate(latitude: 42 + Double($0) * 0.01, longitude: -71)
        })
        let a = TripStop(stationId: "a", name: "A", lat: 42.005, lon: -71)
        let b = TripStop(stationId: "b", name: "B", lat: 42.03, lon: -71)
        let c = TripStop(stationId: "c", name: "C", lat: 42.015, lon: -71)
        let distant = TripStop(stationId: "d", name: "D", lat: 42.03, lon: -70.9)
        XCTAssertNil(TripRoutePath.coordinates(stops: [a, b, c], traces: [trace]))
        XCTAssertNil(TripRoutePath.coordinates(stops: [a, distant], traces: [trace]))
        XCTAssertNil(TripRoutePath.coordinates(stops: [a, b], traces: []))
    }

    func testTripRoutePathChoosesShapeMatchingIntermediateStops() throws {
        let straight = RouteTrace(id: "straight", routeId: "Red", line: .red, coordinates: [
            MapCoordinate(latitude: 42, longitude: -71),
            MapCoordinate(latitude: 42.02, longitude: -71),
        ])
        let curved = RouteTrace(id: "curved", routeId: "Red", line: .red, coordinates: [
            MapCoordinate(latitude: 42, longitude: -71),
            MapCoordinate(latitude: 42.01, longitude: -71.01),
            MapCoordinate(latitude: 42.02, longitude: -71),
        ])
        let stops = [
            TripStop(stationId: "a", name: "A", lat: 42, lon: -71),
            TripStop(stationId: "b", name: "B", lat: 42.01, lon: -71.01),
            TripStop(stationId: "c", name: "C", lat: 42.02, lon: -71),
        ]
        let path = try XCTUnwrap(TripRoutePath.coordinates(stops: stops, traces: [straight, curved]))
        XCTAssertEqual(path.count, 3)
        XCTAssertEqual(path[1].longitude, -71.01, accuracy: 0.000001)
    }

    func testTripRoutePathClipsTwoStopsOnSameSegment() throws {
        let trace = RouteTrace(id: "red", routeId: "Red", line: .red, coordinates: [
            MapCoordinate(latitude: 42, longitude: -71),
            MapCoordinate(latitude: 42.01, longitude: -71),
        ])
        let stops = [
            TripStop(stationId: "a", name: "A", lat: 42.002, lon: -71),
            TripStop(stationId: "b", name: "B", lat: 42.008, lon: -71),
        ]
        let path = try XCTUnwrap(TripRoutePath.coordinates(stops: stops, traces: [trace]))
        XCTAssertEqual(path.count, 2)
        XCTAssertEqual(path[0].latitude, 42.002, accuracy: 0.000001)
        XCTAssertEqual(path[1].latitude, 42.008, accuracy: 0.000001)
    }

    private func vehicle(_ id: String, route: String, direction: Int? = 0, branch: String? = nil) -> Vehicle {
        Vehicle(id: id, routeId: route, tripId: nil, directionId: direction, branchId: branch, label: id,
                lat: 42.3, lon: -71.0, bearing: nil, speedMps: nil, status: nil, updatedAt: nil)
    }

    private let routes: [String: RouteInfo] = Dictionary(uniqueKeysWithValues: [
        RouteInfo(id: "Red", name: "Red Line", color: nil),
        RouteInfo(id: "Orange", name: "Orange Line", color: nil),
        RouteInfo(id: "CR-Fitchburg", name: "Fitchburg Line", color: nil),
        RouteInfo(id: "CR-Lowell", name: "Lowell Line", color: nil),
    ].map { ($0.id, $0) })

    private lazy var fleet = [
        vehicle("red1", route: "Red", direction: 0, branch: "Red-1"),
        vehicle("red2", route: "Red", direction: 1, branch: "Red-3"),
        vehicle("org", route: "Orange", direction: 1),
        vehicle("fit", route: "CR-Fitchburg", direction: 0),
        vehicle("low", route: "CR-Lowell", direction: 1),
        vehicle("sl", route: "741", direction: 0),
        vehicle("bus", route: "1", direction: 0),
    ]

    private func ids(_ f: VehicleFilter) -> Set<String> { Set(f.apply(to: fleet).map(\.id)) }

    func testNothingShowsWhenNoLineIsEnabled() {
        XCTAssertTrue(ids(VehicleFilter(routes: routes)).isEmpty)
    }

    func testEnabledLinesShowOnlyTheirVehicles() {
        XCTAssertEqual(ids(VehicleFilter(enabledLines: [.red], routes: routes)), ["red1", "red2"])
        XCTAssertEqual(ids(VehicleFilter(enabledLines: [.commuter, .orange], routes: routes)), ["fit", "low", "org"])
    }

    func testSilverLineIsRecognisedAndOtherBusesAreNever() {
        XCTAssertEqual(ids(VehicleFilter(enabledLines: [.silver], routes: routes)), ["sl"])
        XCTAssertFalse(ids(VehicleFilter(enabledLines: Set(LineGroup.allCases), routes: routes)).contains("bus"))
    }

    func testNoDirectionSelectedShowsBothDirections() {
        XCTAssertEqual(ids(VehicleFilter(enabledLines: [.red], routes: routes)).count, 2)
    }

    func testDirectionFilter() {
        let out = VehicleFilter(enabledLines: [.red], enabledDirections: [.outbound], routes: routes)
        XCTAssertEqual(ids(out), ["red1"])
        let inb = VehicleFilter(enabledLines: [.red], enabledDirections: [.inbound], routes: routes)
        XCTAssertEqual(ids(inb), ["red2"])
    }

    func testSelectedRouteRestrictsItsLineOnly() {
        let f = VehicleFilter(enabledLines: [.commuter, .red], enabledRoutes: ["CR-Fitchburg"], routes: routes)
        XCTAssertEqual(ids(f), ["fit", "red1", "red2"])
    }

    func testSelectedBranchRestrictsToThatBranch() {
        let branches = [Branch(id: "Red-1", routeId: "Red", name: "Ashmont"), Branch(id: "Red-3", routeId: "Red", name: "Braintree")]
        let f = VehicleFilter(enabledLines: [.red], enabledRoutes: ["Red-3"], routes: routes, branches: branches)
        XCTAssertEqual(ids(f), ["red2"])
    }

    func testAlertMatchesOnlySelectedRouteIds() {
        let selectedAlert = TransitAlert(id: "selected", effect: "delay", header: "Delay", routeIds: ["CR-Worcester"])
        let otherAlert = TransitAlert(id: "other", effect: "delay", header: "Delay", routeIds: ["CR-Fitchburg"])

        XCTAssertTrue(selectedAlert.affectsAnyRoute(in: ["CR-Worcester"]))
        XCTAssertFalse(otherAlert.affectsAnyRoute(in: ["CR-Worcester"]))
    }

    func testApproachingListHidesTrainsThatHavePassed() {
        let f = VehicleFilter(enabledLines: [.red, .orange], approaching: [.red: ["red2"]], routes: routes)
        XCTAssertEqual(ids(f), ["red2", "org"])
    }

    func testUnknownApproachingDataDoesNotHideTrains() {
        XCTAssertEqual(ids(VehicleFilter(enabledLines: [.red], approaching: [:], routes: routes)), ["red1", "red2"])
    }

    func testVehicleWithUnknownDirectionStillShowsWhenFilteringDirection() {
        let f = VehicleFilter(enabledLines: [.red], enabledDirections: [.inbound], routes: routes)
        XCTAssertEqual(f.apply(to: [vehicle("x", route: "Red", direction: nil)]).map(\.id), ["x"])
    }
}

final class LineGroupTests: XCTestCase {
    func testRouteIdMapping() {
        XCTAssertEqual(LineGroup(routeId: "Red"), .red)
        XCTAssertEqual(LineGroup(routeId: "Mattapan"), .red)
        XCTAssertEqual(LineGroup(routeId: "Green-D"), .green)
        XCTAssertEqual(LineGroup(routeId: "CR-Providence"), .commuter)
        XCTAssertEqual(LineGroup(routeId: "746"), .silver)
        XCTAssertNil(LineGroup(routeId: "39"))
    }
    func testPreferencesStartWithEverythingOff() {
        let p = Preferences()
        XCTAssertTrue(p.lines.isEmpty)
        XCTAssertTrue(p.directions.isEmpty)
        XCTAssertTrue(p.routes.isEmpty)
        XCTAssertTrue(p.onlyApproaching)
    }

    func testDirectionLabels() {
        XCTAssertEqual(Direction.inbound.label, "Inbound")
        XCTAssertEqual(Direction(rawValue: 0), .outbound)
    }
}

final class EncodedPolylineTests: XCTestCase {
    func testDecodesEncodedCoordinates() throws {
        let coordinates = try XCTUnwrap(EncodedPolyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@"))
        XCTAssertEqual(coordinates.count, 3)
        XCTAssertEqual(coordinates[0].latitude, 38.5, accuracy: 0.00001)
        XCTAssertEqual(coordinates[0].longitude, -120.2, accuracy: 0.00001)
        XCTAssertEqual(coordinates[2].latitude, 43.252, accuracy: 0.00001)
        XCTAssertEqual(coordinates[2].longitude, -126.453, accuracy: 0.00001)
    }

    func testRejectsMalformedEncodedCoordinates() {
        XCTAssertNil(EncodedPolyline.decode("~"))
    }
}


final class RouteCacheTests: XCTestCase {
    private func snapshot(savedAt: Date) -> RouteSnapshot {
        RouteSnapshot(
            savedAt: savedAt,
            routes: [RouteInfo(id: "Orange", name: "Orange Line", color: "#ED8B00")],
            traces: [RouteTrace(id: "Orange:1", routeId: "Orange", line: .orange,
                                coordinates: [MapCoordinate(latitude: 42.3, longitude: -71.1)])],
            directions: [RouteDirection(routeId: "Orange", direction: .outbound, startStop: "Oak Grove", endStop: "Forest Hills")]
        )
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("route-\(UUID().uuidString).json")
    }

    func testRoundTripWithinMaxAge() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        RouteCache.save(snapshot(savedAt: Date()), to: url)
        let loaded = RouteCache.load(from: url)
        XCTAssertEqual(loaded?.traces.first?.routeId, "Orange")
        XCTAssertEqual(loaded?.directions.first?.endStop, "Forest Hills")
    }

    func testExpiredSnapshotIsIgnored() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        RouteCache.save(snapshot(savedAt: Date().addingTimeInterval(-8 * 24 * 3600)), to: url)
        XCTAssertNil(RouteCache.load(from: url))
    }

    func testMissingFileIsIgnored() {
        XCTAssertNil(RouteCache.load(from: tempURL()))
    }
}
