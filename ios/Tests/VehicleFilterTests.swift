import XCTest
@testable import TransitApp

final class VehicleFilterTests: XCTestCase {
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
