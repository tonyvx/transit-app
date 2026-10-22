import CoreLocation
import XCTest
@testable import TransitApp

final class LivePredictionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func network() -> TransitNetwork {
        let a = NetStation(id: "A", name: "A", lat: 42.30, lon: -71.10)
        let b = NetStation(id: "B", name: "B", lat: 42.31, lon: -71.10)
        return TransitNetwork(
            stations: ["A": a, "B": b],
            patterns: [NetPattern(id: "P", routeId: "Red", directionId: 0, stops: [PatternStop(stationId: "A", offset: 0), PatternStop(stationId: "B", offset: 600)])])
    }

    private func plan(_ provider: FakeProvider) async throws -> Itinerary {
        let planner = TripPlanner(provider: provider, network: network(), accessLeg: { _, _, _ in (60, 80) })
        let a = PlanPoint(name: "A", lat: 42.30, lon: -71.10)
        let b = PlanPoint(name: "B", lat: 42.31, lon: -71.10)
        return try await planner.plan(from: a, to: b, fromMode: .walk, toMode: .walk, departAt: t0)[0]
    }

    func testScheduledOnlyWhenNoPredictions() async throws {
        let p = FakeProvider(deps: [("T1", 300)], arrive: ["T1": 900], live: [:])
        let leg = try await plan(p).transitLegs[0]
        XCTAssertFalse(leg.isLive)
        XCTAssertEqual(leg.start, t0.addingTimeInterval(300))
        XCTAssertEqual(leg.end, t0.addingTimeInterval(900))
    }

    func testLiveTimesReplaceSchedule() async throws {
        let p = FakeProvider(deps: [("T1", 300)], arrive: ["T1": 900],
                             live: ["T1": LiveTimes(depart: t0.addingTimeInterval(420), arrive: t0.addingTimeInterval(1_050))])
        let leg = try await plan(p).transitLegs[0]
        XCTAssertTrue(leg.isLive)
        XCTAssertEqual(leg.delaySeconds, 120)
        XCTAssertEqual(leg.start, t0.addingTimeInterval(420))
        XCTAssertEqual(leg.end, t0.addingTimeInterval(1_050))
    }

    func testDelayCarriesToArrivalWhenOnlyDepartureIsPredicted() async throws {
        let p = FakeProvider(deps: [("T1", 300)], arrive: ["T1": 900], live: ["T1": LiveTimes(depart: t0.addingTimeInterval(480))])
        let leg = try await plan(p).transitLegs[0]
        XCTAssertEqual(leg.end, t0.addingTimeInterval(1_080))
    }

    func testCancelledTripIsSkipped() async throws {
        let p = FakeProvider(deps: [("T1", 300), ("T2", 900)], arrive: ["T1": 900, "T2": 1_500],
                             live: ["T1": LiveTimes(cancelled: true)])
        let leg = try await plan(p).transitLegs[0]
        XCTAssertEqual(leg.start, t0.addingTimeInterval(900))
    }

    func testDelayedTripOvertakenByNextOneIsNotChosen() async throws {
        let p = FakeProvider(deps: [("T1", 300), ("T2", 600)], arrive: ["T1": 900, "T2": 1_200],
                             live: ["T1": LiveTimes(depart: t0.addingTimeInterval(1_000), arrive: t0.addingTimeInterval(1_600))])
        let leg = try await plan(p).transitLegs[0]
        XCTAssertEqual(leg.start, t0.addingTimeInterval(600))
    }

    func testLeaveByUsesLiveDeparture() async throws {
        let p = FakeProvider(deps: [("T1", 300)], arrive: ["T1": 900], live: ["T1": LiveTimes(depart: t0.addingTimeInterval(600))])
        let it = try await plan(p)
        XCTAssertEqual(it.leaveBy, t0.addingTimeInterval(540))
    }
}

final class ArriveByTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func planner(_ provider: FakeProvider) -> TripPlanner {
        let a = NetStation(id: "A", name: "A", lat: 42.30, lon: -71.10)
        let b = NetStation(id: "B", name: "B", lat: 42.31, lon: -71.10)
        let net = TransitNetwork(stations: ["A": a, "B": b],
                                 patterns: [NetPattern(id: "P", routeId: "Red", directionId: 0, stops: [PatternStop(stationId: "A", offset: 0), PatternStop(stationId: "B", offset: 600)])])
        return TripPlanner(provider: provider, network: net, accessLeg: { _, _, _ in (60, 80) })
    }

    private let a = PlanPoint(name: "A", lat: 42.30, lon: -71.10)
    private let b = PlanPoint(name: "B", lat: 42.31, lon: -71.10)

    func testPicksLatestTripThatArrivesInTime() async throws {
        // Trips arrive at 30, 40 and 50 minutes. The rider must be there by 45 minutes.
        let p = FakeProvider(deps: [("T1", 1_200), ("T2", 1_800), ("T3", 2_400)], arrive: ["T1": 1_800, "T2": 2_400, "T3": 3_000], live: [:])
        let r = try await planner(p).plan(from: a, to: b, fromMode: .walk, toMode: .walk, arriveBy: t0.addingTimeInterval(45 * 60 + 80), now: t0)
        XCTAssertEqual(r[0].transitLegs[0].start, t0.addingTimeInterval(1_800))
        XCTAssertTrue(r.allSatisfy { $0.arriveAt <= t0.addingTimeInterval(45 * 60 + 80) })
    }

    func testFailsWhenNothingArrivesInTime() async {
        let p = FakeProvider(deps: [("T1", 1_200)], arrive: ["T1": 1_800], live: [:])
        do {
            _ = try await planner(p).plan(from: a, to: b, fromMode: .walk, toMode: .walk, arriveBy: t0.addingTimeInterval(600), now: t0)
            XCTFail("expected an error")
        } catch {}
    }

    func testDeadlineInThePastFails() async {
        let p = FakeProvider(deps: [("T1", 1_200)], arrive: ["T1": 1_800], live: [:])
        do {
            _ = try await planner(p).plan(from: a, to: b, fromMode: .walk, toMode: .walk, arriveBy: t0.addingTimeInterval(-60), now: t0)
            XCTFail("expected an error")
        } catch {}
    }
}

struct FakeProvider: TransitProvider {
    let deps: [(String, TimeInterval)]
    let arrive: [String: TimeInterval]
    let live: [String: LiveTimes]
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    init(deps: [(String, TimeInterval)], arrive: [String: TimeInterval], live: [String: LiveTimes]) {
        self.deps = deps; self.arrive = arrive; self.live = live
    }

    func departures(routeId: String, directionId: Int, stationId: String, after: Date, limit: Int) async throws -> [ScheduledDeparture] {
        deps.map { ScheduledDeparture(tripId: $0.0, patternId: "P", time: base.addingTimeInterval($0.1)) }
    }
    func stopTime(tripId: String, stationId: String, on day: Date) async throws -> Date? { arrive[tripId].map { base.addingTimeInterval($0) } }
    func liveTimes(tripId: String, from: String, to: String) async throws -> LiveTimes? { live[tripId] }

    func vehicles() async throws -> [Vehicle] { [] }
    func alerts() async throws -> [TransitAlert] { [] }
    func routes() async throws -> [RouteInfo] { [] }
    func branches() async throws -> [Branch] { [] }
    func stations(routeIds: [String]) async throws -> [StopInfo] { [] }
    func origins(routeId: String, directionId: Int) async throws -> [StopInfo] { [] }
    func network() async throws -> TransitNetwork { TransitNetwork(stations: [:], patterns: []) }
    func arrivals(stopId: String, routeIds: [String]) async throws -> [Arrival] { [] }
}
