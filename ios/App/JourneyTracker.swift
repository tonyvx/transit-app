@preconcurrency import ActivityKit
import CoreLocation
import Foundation
import Observation
import UIKit

struct JourneySuggestion: Identifiable {
    let id: String
    let routeName: String
    let trainLabel: String
    let boardName: String
    let destinationName: String
    let initialStopIndex: Int
}

enum TripBoardingMatcher {
    static func candidate(
        itinerary: Itinerary,
        vehicles: [Vehicle],
        pings: [Ping],
        now: Date
    ) -> (leg: ItineraryLeg, vehicle: Vehicle, stopIndex: Int)? {
        guard let latestPing = pings.last,
              now.timeIntervalSince(latestPing.timestamp) <= 45,
              latestPing.accuracyM <= 100,
              let match = TrainMatcher.match(pings: pings, vehicles: vehicles),
              match.confidence >= TrainMatcher.minConfidence,
              let vehicle = vehicles.first(where: { $0.id == match.vehicleId }),
              CLLocation(latitude: latestPing.lat, longitude: latestPing.lon)
                .distance(from: CLLocation(latitude: vehicle.lat, longitude: vehicle.lon)) <= 300
        else { return nil }

        guard let leg = itinerary.transitLegs.first(where: {
            guard let tripId = $0.tripId else { return false }
            return vehicle.tripId == tripId
                && vehicle.routeId == $0.routeId
                && now >= $0.start.addingTimeInterval(-15 * 60)
                && now <= $0.end.addingTimeInterval(5 * 60)
        }) else { return nil }
        let index = TripProgress.nearestStopIndex(
            stops: leg.tripStops,
            latitude: vehicle.lat,
            longitude: vehicle.lon,
            radiusM: 800
        ) ?? 0
        return (leg, vehicle, index)
    }
}

enum TripProgress {
    static func advancedStopIndex(current: Int, stops: [TripStop], latitude: Double, longitude: Double, radiusM: Double = 350) -> Int {
        guard stops.indices.contains(current) else { return current }
        let position = CLLocation(latitude: latitude, longitude: longitude)
        let remaining = stops.indices.dropFirst(current)
        guard let nearest = remaining.min(by: {
            distance(position, stop: stops[$0]) < distance(position, stop: stops[$1])
        }), nearest > current,
              distance(position, stop: stops[nearest]) <= radiusM else { return current }
        return nearest
    }

    static func nearestStopIndex(stops: [TripStop], latitude: Double, longitude: Double, radiusM: Double) -> Int? {
        let position = CLLocation(latitude: latitude, longitude: longitude)
        guard let nearest = stops.indices.min(by: {
            distance(position, stop: stops[$0]) < distance(position, stop: stops[$1])
        }), distance(position, stop: stops[nearest]) <= radiusM else { return nil }
        return nearest
    }

    private static func distance(_ position: CLLocation, stop: TripStop) -> CLLocationDistance {
        position.distance(from: CLLocation(latitude: stop.lat, longitude: stop.lon))
    }
}

@MainActor
@Observable
final class JourneyTracker {
    private(set) var pendingSuggestion: JourneySuggestion?
    private(set) var isActive = false
    private(set) var statusMessage: String?
    private(set) var nextStopName = ""
    private(set) var stopsRemaining = 0

    private var selectedItinerary: Itinerary?
    private var transitLegs: [ItineraryLeg] = []
    private var activeLegIndex = 0
    private var passedStopIndex = 0
    private var dismissedSuggestionIds = Set<String>()
    private var notifiedSuggestionIds = Set<String>()
    private var activity: Activity<TripActivityAttributes>?
    private var lastActivityUpdate = Date.distantPast
    private var lastActivityState: TripActivityAttributes.ContentState?
    private var locationTracker: LocationTracker?
    private var routeNames: [String: String] = [:]

    var currentRouteName: String {
        routeNames[currentLeg?.routeId ?? ""] ?? currentLeg?.routeId ?? "Train"
    }

    func evaluate(
        itinerary: Itinerary?,
        vehicles: [Vehicle],
        pings: [Ping],
        routeNames: [String: String],
        fetchedAt: Date,
        now: Date = Date()
    ) async {
        self.routeNames = routeNames
        if isActive {
            if locationTracker?.backgroundTripTrackingEnabled == true,
               locationTracker?.authorization == .authorizedAlways {
                statusMessage = nil
            }
            await updateActiveJourney(vehicles: vehicles, pings: pings, fetchedAt: fetchedAt, now: now)
        } else if pendingSuggestion == nil, let itinerary {
            findBoardingCandidate(itinerary: itinerary, vehicles: vehicles, pings: pings, routeNames: routeNames, now: now)
        }
    }

    func dismissSuggestion() {
        if let pendingSuggestion {
            dismissedSuggestionIds.insert(pendingSuggestion.id)
            Notifier.cancelBoardingPrompt(id: pendingSuggestion.id)
        }
        pendingSuggestion = nil
    }

    func confirmSuggestion(
        itinerary: Itinerary?,
        location: LocationTracker,
        routeNames: [String: String]
    ) async {
        guard let suggestion = pendingSuggestion,
              let itinerary,
              let legIndex = itinerary.transitLegs.firstIndex(where: { $0.tripId == suggestion.id }) else {
            dismissSuggestion()
            statusMessage = "That trip is no longer selected. Plan it again to start tracking."
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            dismissSuggestion()
            statusMessage = "Live Activities are disabled. Enable them in Settings to track this trip."
            return
        }

        selectedItinerary = itinerary
        transitLegs = itinerary.transitLegs
        activeLegIndex = legIndex
        passedStopIndex = suggestion.initialStopIndex
        Notifier.cancelBoardingPrompt(id: suggestion.id)
        pendingSuggestion = nil
        locationTracker = location
        location.beginTripTracking()
        let canRunInBackground = location.authorization == .authorizedAlways && location.backgroundTripTrackingEnabled

        guard let leg = currentLeg, leg.tripStops.count > 1 else {
            statusMessage = "This itinerary has no stop-by-stop data for the selected train."
            isActive = false
            return
        }
        let routeName = routeNames[leg.routeId ?? ""] ?? leg.routeId ?? "Train"
        let initialStatus = canRunInBackground ? "Trip confirmed · tracking" : "Trip confirmed · foreground only"
        let state = contentState(for: leg, routeName: routeName, status: initialStatus)
        let attributes = TripActivityAttributes(
            origin: itinerary.legs.first?.fromName ?? leg.fromName,
            routeName: routeName
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nowPlus(minutes: 2)),
                pushType: nil
            )
            isActive = true
            statusMessage = canRunInBackground ? nil : "For Lock Screen updates while the app is closed, enable background trip updates in Preferences."
            lastActivityUpdate = Date()
            lastActivityState = state
        } catch {
            isActive = false
            statusMessage = "Couldn't start the Live Activity. Check Live Activities in Settings."
            location.endTripTracking()
        }
    }

    func endTrip(location: LocationTracker) async {
        guard let activity else { return }
        let final = TripActivityAttributes.ContentState(
            nextStop: "Trip ended",
            routeName: currentRouteName,
            destination: selectedItinerary?.legs.last?.toName ?? "Destination",
            stopsRemaining: 0,
            status: "Trip tracking stopped",
            lastUpdated: Date()
        )
        await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
        clear(location: location)
    }

    private var currentLeg: ItineraryLeg? {
        transitLegs.indices.contains(activeLegIndex) ? transitLegs[activeLegIndex] : nil
    }

    private func findBoardingCandidate(
        itinerary: Itinerary,
        vehicles: [Vehicle],
        pings: [Ping],
        routeNames: [String: String],
        now: Date
    ) {
        guard let (leg, vehicle, stopIndex) = TripBoardingMatcher.candidate(itinerary: itinerary, vehicles: vehicles, pings: pings, now: now),
              let tripId = leg.tripId,
              !dismissedSuggestionIds.contains(tripId) else { return }
        let suggestion = JourneySuggestion(
            id: tripId,
            routeName: routeNames[leg.routeId ?? ""] ?? leg.routeId ?? "Train",
            trainLabel: vehicle.label ?? "Train",
            boardName: leg.fromName,
            destinationName: leg.toName,
            initialStopIndex: stopIndex
        )
        pendingSuggestion = suggestion
        if UIApplication.shared.applicationState != .active, notifiedSuggestionIds.insert(tripId).inserted {
            Task {
                await Notifier.scheduleBoardingPrompt(
                    id: tripId,
                    routeName: suggestion.routeName,
                    destination: suggestion.destinationName
                )
            }
        }
    }

    private func updateActiveJourney(vehicles: [Vehicle], pings: [Ping], fetchedAt: Date, now: Date) async {
        guard let leg = currentLeg, let tripId = leg.tripId else { return }
        guard let ping = pings.last,
              now.timeIntervalSince(ping.timestamp) <= 90,
              ping.accuracyM <= 150 else {
            await updateActivity(leg: leg, status: "Waiting for GPS update", now: now)
            return
        }
        let rider = CLLocation(latitude: ping.lat, longitude: ping.lon)
        let vehicle = vehicles.first(where: { $0.tripId == tripId && $0.routeId == leg.routeId })
        let trainPositionIsFresh = vehicle != nil && now.timeIntervalSince(fetchedAt) <= 90
        if trainPositionIsFresh, let vehicle,
           rider.distance(from: CLLocation(latitude: vehicle.lat, longitude: vehicle.lon)) > 600 {
            await updateActivity(leg: leg, status: "GPS and train position do not match", now: now)
            return
        }

        let stops = leg.tripStops
        guard stops.count > 1 else { return }
        let position: CLLocationCoordinate2D
        if trainPositionIsFresh, let vehicle {
            position = CLLocationCoordinate2D(latitude: vehicle.lat, longitude: vehicle.lon)
        } else {
            position = CLLocationCoordinate2D(latitude: ping.lat, longitude: ping.lon)
        }
        passedStopIndex = TripProgress.advancedStopIndex(
            current: passedStopIndex,
            stops: stops,
            latitude: position.latitude,
            longitude: position.longitude
        )

        if passedStopIndex == stops.count - 1 {
            if activeLegIndex + 1 < transitLegs.count {
                activeLegIndex += 1
                passedStopIndex = 0
                if let nextLeg = currentLeg {
                    await updateActivity(leg: nextLeg, status: "Transfer · checking next train", now: now)
                }
            } else {
                await finishAtDestination()
            }
            return
        }
        await updateActivity(leg: leg, status: trainPositionIsFresh ? "Live · GPS and train matched" : "Live · GPS position", now: now)
    }

    private func updateActivity(leg: ItineraryLeg, status: String, now: Date) async {
        guard let activity else { return }
        let routeName = routeNames[leg.routeId ?? ""] ?? leg.routeId ?? "Train"
        var state = contentState(for: leg, routeName: routeName, status: status)
        let stateChanged = state.nextStop != lastActivityState?.nextStop
            || state.routeName != lastActivityState?.routeName
            || state.destination != lastActivityState?.destination
            || state.stopsRemaining != lastActivityState?.stopsRemaining
            || state.status != lastActivityState?.status
        guard stateChanged || now.timeIntervalSince(lastActivityUpdate) >= 60 else { return }
        state.lastUpdated = now
        await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(2 * 60)))
        lastActivityUpdate = now
        lastActivityState = state
    }

    private func contentState(for leg: ItineraryLeg, routeName: String, status: String) -> TripActivityAttributes.ContentState {
        let stops = leg.tripStops
        let nextIndex = min(passedStopIndex + 1, max(0, stops.count - 1))
        let next = stops.indices.contains(nextIndex) ? stops[nextIndex].name : leg.toName
        let count = max(0, stops.count - 1 - passedStopIndex)
        nextStopName = next
        stopsRemaining = count
        return TripActivityAttributes.ContentState(
            nextStop: next,
            routeName: routeName,
            destination: leg.toName,
            stopsRemaining: count,
            status: status,
            lastUpdated: Date()
        )
    }

    private func finishAtDestination() async {
        if let activity {
            let final = TripActivityAttributes.ContentState(
                nextStop: currentLeg?.toName ?? "Destination",
                routeName: currentRouteName,
                destination: selectedItinerary?.legs.last?.toName ?? currentLeg?.toName ?? "Destination",
                stopsRemaining: 0,
                status: "Arrived",
                lastUpdated: Date()
            )
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(5 * 60)))
        }
        if let locationTracker { clear(location: locationTracker) }
    }

    private func clear(location: LocationTracker) {
        isActive = false
        activity = nil
        selectedItinerary = nil
        transitLegs = []
        activeLegIndex = 0
        passedStopIndex = 0
        lastActivityState = nil
        nextStopName = ""
        stopsRemaining = 0
        location.endTripTracking()
    }

    private func nowPlus(minutes: Double) -> Date { Date().addingTimeInterval(minutes * 60) }
}
