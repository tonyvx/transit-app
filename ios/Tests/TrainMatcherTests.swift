import XCTest
@testable import TransitApp

final class TrainMatcherTests: XCTestCase {
    private let base = (lat: 42.35, lon: -71.06)
    /// About 111 m per 0.001 degrees of latitude.
    private let metersPerMilliDegree = 111.0

    private func vehicle(_ id: String, northM: Double = 0, bearing: Double? = nil, speed: Double? = nil) -> Vehicle {
        Vehicle(id: id, routeId: "CR-Worcester", tripId: nil, directionId: 0, branchId: nil, label: id,
                lat: base.lat + northM / 111_195, lon: base.lon, bearing: bearing, speedMps: speed, status: nil, updatedAt: nil)
    }

    private func pings(count: Int = 6, northM: Double = 0, accuracy: Double = 20, speed: Double? = nil, heading: Double? = nil) -> [Ping] {
        (0..<count).map { i in
            Ping(lat: base.lat + northM / 111_195, lon: base.lon, accuracyM: accuracy, speedMps: speed, heading: heading,
                 timestamp: Date().addingTimeInterval(Double(i) * -20))
        }
    }

    func testMatchesTheTrainRightNextToYou() throws {
        let match = try XCTUnwrap(TrainMatcher.match(pings: pings(), vehicles: [vehicle("near", northM: 30), vehicle("far", northM: 5000)]))
        XCTAssertEqual(match.vehicleId, "near")
        XCTAssertGreaterThanOrEqual(match.confidence, TrainMatcher.minConfidence)
        XCTAssertEqual(match.pings, 6)
    }

    func testNoMatchWithTooFewPings() {
        XCTAssertNil(TrainMatcher.match(pings: pings(count: 2), vehicles: [vehicle("near")]))
    }

    func testPoorAccuracyPingsAreIgnored() {
        XCTAssertNil(TrainMatcher.match(pings: pings(accuracy: 500), vehicles: [vehicle("near")]))
    }

    func testNoMatchWithoutVehicles() {
        XCTAssertNil(TrainMatcher.match(pings: pings(), vehicles: []))
    }

    func testNoMatchWhenEveryTrainIsMoreThanTwoKilometresAway() {
        XCTAssertNil(TrainMatcher.match(pings: pings(), vehicles: [vehicle("far", northM: 2500)]))
    }

    func testTwoTrainsInTheSamePlaceAreTooAmbiguous() {
        XCTAssertNil(TrainMatcher.match(pings: pings(), vehicles: [vehicle("a"), vehicle("b")]))
    }

    func testHeadingBreaksATieBetweenAdjacentTrains() throws {
        // Rider is heading north at 20 m/s. Both trains are at the same spot; only one is also going north.
        let p = pings(speed: 20, heading: 0)
        let match = try XCTUnwrap(TrainMatcher.match(pings: p, vehicles: [
            vehicle("south", bearing: 180, speed: 20), vehicle("north", bearing: 0, speed: 20),
        ]))
        XCTAssertEqual(match.vehicleId, "north")
    }

    func testSpeedMismatchLowersTheScore() throws {
        // A stationary train is a poor match for someone moving at 25 m/s, so the moving one wins.
        let p = pings(speed: 25)
        let match = try XCTUnwrap(TrainMatcher.match(pings: p, vehicles: [vehicle("stopped", speed: 0), vehicle("moving", speed: 24)]))
        XCTAssertEqual(match.vehicleId, "moving")
    }

    func testConfidenceBuckets() {
        XCTAssertEqual(Confidence(0.9), .high)
        XCTAssertEqual(Confidence(0.7), .medium)
        XCTAssertEqual(Confidence(0.3), .low)
    }
}
