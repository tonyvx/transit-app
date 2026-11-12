import SwiftUI

struct HowToView: View {
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    private struct Step: Identifiable {
        let id: String
        let image: String
        let title: String
        let bullets: [String]
    }

    private let steps: [Step] = [
        Step(id: "prefs", image: "howto-prefs", title: "1. Choose your favorite lines",
             bullets: [
                "Tap a route on the map to see its name, directions and endpoints, or use the star to favorite it.",
                "To pick specific routes and branches, open the gear menu and choose Edit favorite lines.",
                "Direction and approaching-train settings save immediately. Favorite chips and alerts reflect your selections."
             ]),
        Step(id: "map", image: "howto-map", title: "2. Watch trains on the map",
             bullets: [
                "Tap a train to see its status. Tap Plan a trip at the top to open the planner.",
                "When viewing a trip, turn on Hide other lines at the bottom left to hide other routes and trains, fade unused route segments, and show only saved-line stations on the trip.",
                "If a route shape cannot be matched, the trip is drawn between stops.",
                "The gear menu contains settings, trip tracking, feedback, terms and MBTA information. If the connection drops, the map shows a banner and the last trains it saw."
             ]),
        Step(id: "station", image: "howto-station", title: "3. Check a station",
             bullets: [
                "Tap a station dot to see arrival times by train number.",
                "Tap the star to save the station, or tap a train number to highlight that train on the map."
             ]),
        Step(id: "alerts", image: "howto-alerts", title: "4. Read alerts",
             bullets: [
                "Tap the alert count to the right of Plan a trip.",
                "Favorite-line alerts are grouped by direction and colored by line. Other alerts are collapsed at the bottom."
             ]),
        Step(id: "planner", image: "howto-planner", title: "5. Plan a trip",
             bullets: [
                "Expand Saved trips to see saved journeys and reminders.",
                "Choose Walk, Drive, Scooter or Bike for both station legs. Use the mode icon beside either address to change that leg.",
                "Enter each address and leave the field to look it up, or use the location and pin buttons. Trips are found automatically when both locations are ready; tap GO to search again.",
                "Use Swap to reverse the endpoints or Clear to reset the trip. Choose Leave now, Depart at or Arrive by, then tap GO after changing the time.",
                "Results show live predictions when available, scheduled times otherwise, and estimated miles. Transit distances follow straight lines between stops; walking transfers are approximations.",
                "Tap a result to show it on the map. Save trips and set weekday reminders in the planner."
             ]),
        Step(id: "triptracking", image: "howto-triptracking", title: "6. Track a trip to your stop",
             bullets: [
                "Tracking is optional. For updates while your phone is locked, enable Allow background trip updates in the gear menu and choose Always in Location Services.",
                "When GPS matches your selected train, confirm that you're aboard. The Lock Screen Live Activity shows the next stop and stops remaining.",
                "Allow notifications for a confirmation prompt while the app is in the background. End tracking when your trip is over. Location stays on your phone."
             ]),
    ]

    var body: some View {
        if embedded { content } else { NavigationStack { content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } } }
    }

    private var content: some View {
            ScrollView {
                VStack(spacing: 28) {
                    Text("Location stays on your phone. Transit data comes from the MBTA.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(steps) { step in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(step.title).font(.headline)
                            ForEach(step.bullets.indices, id: \.self) { index in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•").accessibilityHidden(true)
                                    Text(step.bullets[index])
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Image(step.image)
                                .resizable().scaledToFit()
                                .frame(maxWidth: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.quaternary))
                                .frame(maxWidth: .infinity)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("How to use")
            .navigationBarTitleDisplayMode(.inline)
    }
}
