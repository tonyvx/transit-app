import XCTest
@testable import TransitApp

final class RouterTests: XCTestCase {
    /// Stations sit on a line of longitude at about 1.1 km spacing, far apart enough that nothing is within walking transfer range.
    private func station(_ id: String, _ index: Double) -> NetStation {
        NetStation(id: id, name: id, lat: 42.0 + index * 0.01, lon: -71.0)
    }

    private func stops(_ pairs: [(String, Double)]) -> [PatternStop] {
        pairs.map { PatternStop(stationId: $0.0, offset: $0.1) }
    }

    private func network(_ stations: [NetStation], _ patterns: [NetPattern]) -> TransitNetwork {
        TransitNetwork(stations: Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) }), patterns: patterns)
    }

    private func transitLegs(_ plan: RoutePlan) -> [TransitLeg] {
        plan.legs.compactMap { if case .transit(let t) = $0 { t } else { nil } }
    }

    func testDirectRideCostsAccessPlusBoardingPlusRide() throws {
        let net = network([station("A", 0), station("B", 1), station("C", 2)],
                          [NetPattern(id: "P1", routeId: "Red", directionId: 0, stops: stops([("A", 0), ("B", 300), ("C", 600)]))])
        let plan = try XCTUnwrap(Router(network: net).plan(from: "A", startCost: 100, targets: ["C": 50]))
        let legs = transitLegs(plan)
        XCTAssertEqual(legs.count, 1)
        XCTAssertEqual(legs[0].stationIds, ["A", "B", "C"])
        XCTAssertEqual(legs[0].rideSeconds, 600)
        // 100 access + (240 wait + 120 transfer penalty) + 600 ride + 50 egress
        XCTAssertEqual(plan.cost, 1110, accuracy: 0.001)
        XCTAssertEqual(plan.boardStation, "A")
        XCTAssertEqual(plan.alightStation, "C")
    }

    func testCommuterRailHasLongerBoardingWaitThanSubway() throws {
        func cost(_ routeId: String) throws -> Double {
            let net = network([station("A", 0), station("B", 1)],
                              [NetPattern(id: "P", routeId: routeId, directionId: 0, stops: stops([("A", 0), ("B", 600)]))])
            return try XCTUnwrap(Router(network: net).plan(from: "A", startCost: 0, targets: ["B": 0])).cost
        }
        XCTAssertEqual(try cost("Red"), 960, accuracy: 0.001)
        XCTAssertEqual(try cost("CR-Worcester"), 1620, accuracy: 0.001)
        XCTAssertEqual(try cost("741"), 1140, accuracy: 0.001)
    }

    func testTransferBetweenTwoPatternsAtSharedStation() throws {
        let net = network([station("A", 0), station("B", 1), station("C", 2), station("D", 3)], [
            NetPattern(id: "Red1", routeId: "Red", directionId: 0, stops: stops([("A", 0), ("B", 300)])),
            NetPattern(id: "Org1", routeId: "Orange", directionId: 0, stops: stops([("B", 0), ("C", 300), ("D", 600)])),
        ])
        let plan = try XCTUnwrap(Router(network: net).plan(from: "A", startCost: 0, targets: ["D": 0]))
        let legs = transitLegs(plan)
        XCTAssertEqual(legs.map(\.routeId), ["Red", "Orange"])
        XCTAssertEqual(legs[1].stationIds, ["B", "C", "D"])
        XCTAssertEqual(plan.signature, "Red1:A:B>Org1:B:D")
    }

    func testWalkingTransferBetweenNearbyStations() throws {
        // B and B2 are about 111 m apart.
        let b2 = NetStation(id: "B2", name: "B2", lat: 42.01 + 0.001, lon: -71.0)
        let net = network([station("A", 0), station("B", 1), b2, station("C", 3)], [
            NetPattern(id: "P1", routeId: "Red", directionId: 0, stops: stops([("A", 0), ("B", 300)])),
            NetPattern(id: "P2", routeId: "Orange", directionId: 0, stops: stops([("B2", 0), ("C", 300)])),
        ])
        let plan = try XCTUnwrap(Router(network: net).plan(from: "A", startCost: 0, targets: ["C": 0]))
        let transfers = plan.legs.compactMap { leg -> (String, String)? in if case .transfer(let f, let t, _) = leg { (f, t) } else { nil } }
        XCTAssertEqual(transfers.count, 1)
        XCTAssertEqual(transfers[0].0, "B")
        XCTAssertEqual(transfers[0].1, "B2")
        XCTAssertEqual(transitLegs(plan).count, 2)
    }

    func testStationsTooFarApartAreNotWalkTransfers() {
        let far = NetStation(id: "B2", name: "B2", lat: 42.01 + 0.01, lon: -71.0)
        let net = network([station("A", 0), station("B", 1), far, station("C", 3)], [
            NetPattern(id: "P1", routeId: "Red", directionId: 0, stops: stops([("A", 0), ("B", 300)])),
            NetPattern(id: "P2", routeId: "Orange", directionId: 0, stops: stops([("B2", 0), ("C", 300)])),
        ])
        XCTAssertNil(Router(network: net).plan(from: "A", startCost: 0, targets: ["C": 0]))
    }

    func testTrainsOnlyRunInPatternDirection() {
        let net = network([station("A", 0), station("B", 1)],
                          [NetPattern(id: "P", routeId: "Red", directionId: 0, stops: stops([("A", 0), ("B", 300)]))])
        XCTAssertNil(Router(network: net).plan(from: "B", startCost: 0, targets: ["A": 0]))
    }

    func testChoosesTheFasterOfTwoPatterns() throws {
        let net = network([station("A", 0), station("B", 1), station("C", 2)], [
            NetPattern(id: "Local", routeId: "CR-Fitchburg", directionId: 0, stops: stops([("A", 0), ("B", 600), ("C", 1200)])),
            NetPattern(id: "Express", routeId: "CR-Fitchburg", directionId: 0, stops: stops([("A", 0), ("C", 700)])),
        ])
        let plan = try XCTUnwrap(Router(network: net).plan(from: "A", startCost: 0, targets: ["C": 0]))
        XCTAssertEqual(transitLegs(plan).first?.patternId, "Express")
    }

    func testPicksTheCheapestTargetIncludingEgress() throws {
        let net = network([station("A", 0), station("B", 1), station("C", 2)],
                          [NetPattern(id: "P", routeId: "Red", directionId: 0, stops: stops([("A", 0), ("B", 300), ("C", 600)]))])
        let plan = try XCTUnwrap(Router(network: net).plan(from: "A", startCost: 0, targets: ["B": 2000, "C": 0]))
        XCTAssertEqual(plan.alightStation, "C")
    }

    func testNeedsAtLeastOneTrainRide() {
        let near = NetStation(id: "B", name: "B", lat: 42.001, lon: -71.0)
        let net = network([station("A", 0), near], [])
        XCTAssertNil(Router(network: net).plan(from: "A", startCost: 0, targets: ["B": 0]))
    }

    func testStartingAtTheTargetIsIgnored() {
        let net = network([station("A", 0), station("B", 1)],
                          [NetPattern(id: "P", routeId: "Red", directionId: 0, stops: stops([("A", 0), ("B", 300)]))])
        XCTAssertNil(Router(network: net).plan(from: "A", startCost: 0, targets: ["A": 0]))
    }

    func testUnknownSourceReturnsNil() {
        let net = network([station("A", 0)], [])
        XCTAssertNil(Router(network: net).plan(from: "Nope", startCost: 0, targets: ["A": 0]))
    }

    func testNearestStationsAreSortedByDistance() {
        let net = network([station("A", 0), station("B", 1), station("C", 2)], [])
        let near = Router(network: net).nearestStations(lat: 42.019, lon: -71.0)
        XCTAssertEqual(near.map(\.station.id), ["C", "B", "A"])
        XCTAssertEqual(near[0].distanceM, 111, accuracy: 5)
    }

    func testGeoDistanceOneDegreeOfLatitude() {
        XCTAssertEqual(Geo.distanceM(42, -71, 43, -71), 111_195, accuracy: 100)
        XCTAssertEqual(Geo.distanceM(42, -71, 42, -71), 0, accuracy: 0.001)
    }
}

final class AccessModeTests: XCTestCase {
    func testWalkEstimateIncludesStreetCircuity() {
        XCTAssertEqual(AccessMode.walk.estimate(distanceM: 1000), 1000, accuracy: 0.5)
    }

    func testCarAndBikeIncludeParkingOverhead() {
        XCTAssertEqual(AccessMode.car.estimate(distanceM: 0), 240, accuracy: 0.001)
        XCTAssertEqual(AccessMode.bike.estimate(distanceM: 0), 60, accuracy: 0.001)
    }

    func testFasterModesTakeLessTimeOverLongDistances() {
        let d = 4000.0
        XCTAssertLessThan(AccessMode.bike.estimate(distanceM: d), AccessMode.walk.estimate(distanceM: d))
        XCTAssertLessThan(AccessMode.car.estimate(distanceM: d), AccessMode.bike.estimate(distanceM: d))
    }
}
