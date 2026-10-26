import XCTest
@testable import TransitApp

final class JourneyTrackerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var stops: [TripStop] {
        [
            TripStop(stationId: "A", name: "Alpha", lat: 42.3000, lon: -71.1000),
            TripStop(stationId: "B", name: "Bravo", lat: 42.3100, lon: -71.1000),
            TripStop(stationId: "C", name: "Charlie", lat: 42.3200, lon: -71.1000),
        ]
    }

    private func itinerary(tripId: String = "trip-1", start: Date? = nil, end: Date? = nil) -> Itinerary {
        let leg = ItineraryLeg(
            kind: .transit,
            routeId: "Red",
            directionId: 0,
            fromName: "Alpha",
            toName: "Charlie",
            start: start ?? now.addingTimeInterval(-60),
            end: end ?? now.addingTimeInterval(20 * 60),
            stopCount: 2,
            coordinates: [],
            tripId: tripId,
            tripStops: stops
        )
        return Itinerary(legs: [leg], leaveBy: now.addingTimeInterval(-5 * 60), arriveAt: now.addingTimeInterval(20 * 60))
    }

    private func evidence(at coordinate: TripStop, tripId: String = "trip-1", timestamp: Date? = nil) -> ([Vehicle], [Ping]) {
        let vehicle = Vehicle(
            id: "vehicle-1", routeId: "Red", tripId: tripId, directionId: 0,
            branchId: nil, label: "Red Line", lat: coordinate.lat, lon: coordinate.lon,
            bearing: 90, speedMps: 5, status: "IN_TRANSIT_TO", updatedAt: now
        )
        let pings = (0..<3).map { i in
            Ping(lat: coordinate.lat, lon: coordinate.lon, accuracyM: 10, speedMps: 5,
                 heading: 90, timestamp: (timestamp ?? now).addingTimeInterval(Double(i - 2) * 5))
        }
        return ([vehicle], pings)
    }

    func testSuggestsMatchingPlannedTrainWhenGpsConfirmsIt() {
        let (vehicles, pings) = evidence(at: stops[0])
        let result = TripBoardingMatcher.candidate(itinerary: itinerary(), vehicles: vehicles, pings: pings, now: now)
        XCTAssertEqual(result?.leg.tripId, "trip-1")
        XCTAssertEqual(result?.vehicle.id, "vehicle-1")
    }

    func testDoesNotSuggestDifferentTrain() {
        let (vehicles, pings) = evidence(at: stops[0], tripId: "other-trip")
        XCTAssertNil(TripBoardingMatcher.candidate(itinerary: itinerary(), vehicles: vehicles, pings: pings, now: now))
    }

    func testDoesNotSuggestWhenGpsIsStale() {
        let (vehicles, pings) = evidence(at: stops[0], timestamp: now.addingTimeInterval(-60))
        XCTAssertNil(TripBoardingMatcher.candidate(itinerary: itinerary(), vehicles: vehicles, pings: pings, now: now))
    }

    func testDoesNotSuggestOutsidePlannedTripWindow() {
        let (vehicles, pings) = evidence(at: stops[0])
        let later = itinerary(start: now.addingTimeInterval(40 * 60), end: now.addingTimeInterval(60 * 60))
        XCTAssertNil(TripBoardingMatcher.candidate(itinerary: later, vehicles: vehicles, pings: pings, now: now))
    }

    func testProgressAdvancesAtNextStopAndNeverMovesBackward() {
        let atBravo = TripProgress.advancedStopIndex(current: 0, stops: stops, latitude: stops[1].lat, longitude: stops[1].lon)
        XCTAssertEqual(atBravo, 1)
        let afterBravo = TripProgress.advancedStopIndex(current: 1, stops: stops, latitude: stops[0].lat, longitude: stops[0].lon)
        XCTAssertEqual(afterBravo, 1)
    }

    func testProgressDoesNotAdvanceWhenTrainIsFarFromStation() {
        XCTAssertEqual(TripProgress.advancedStopIndex(current: 0, stops: stops, latitude: 42.305, longitude: -71.10), 0)
    }

    func testInitialProgressUsesNearestStationWhenAlreadyOnTheTrain() {
        XCTAssertEqual(
            TripProgress.nearestStopIndex(stops: stops, latitude: stops[1].lat, longitude: stops[1].lon, radiusM: 800),
            1
        )
    }
}
