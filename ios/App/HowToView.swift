import SwiftUI

struct HowToView: View {
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    private struct Step: Identifiable {
        let id: String
        let image: String
        let title: String
        let text: String
    }

    private let steps: [Step] = [
        Step(id: "prefs", image: "howto-prefs", title: "1. Choose your lines",
             text: "Tap a route on the map to add it to your favorite lines and show its trains and stations. Tap it again to remove it. Choose Inbound or Outbound in More."),
        Step(id: "map", image: "howto-map", title: "2. Watch trains on the map",
             text: "All supported route paths are shown. Tap a route to show or hide its trains and stations. Tap a train to see its status. Use Plan a trip at the top to open the planner. Open More for settings and MBTA information. Trains that have already passed you are hidden unless you turn that off."),
        Step(id: "station", image: "howto-station", title: "3. Check a station",
             text: "Tap a station dot to see arrival times by train number. Tap the star in the station sheet to save it as a favorite. Tap a train number to close the sheet and highlight that train on the map with a halo."),
        Step(id: "alerts", image: "howto-alerts", title: "4. Read alerts",
             text: "Tap the alert count to the right of Plan a trip. Alerts for your lines come first. Lines that start ahead of you show the drive time to get there. Other lines are collapsed."),
        Step(id: "planner", image: "howto-planner", title: "5. Plan a trip",
             text: "Enter an address and tap Search this location (or press Search on the keyboard), use your location, or drop a pin. Find trips stays at the bottom of the planner. Choose how you get to and from stations, then pick Leave now, Depart at or Arrive by. Results use live predictions when available and schedules otherwise. Tap a result to show it on the map. Save trips and set weekday reminders in the planner."),
        Step(id: "triptracking", image: "howto-triptracking", title: "6. Track a trip to your stop",
             text: "Trip tracking is optional. In Preferences, enable Allow background trip updates and choose Always in Location Services to get updates while the phone is locked. When GPS matches your selected train, confirm that you're aboard. The Lock Screen Live Activity shows the next stop and stops remaining. Allow notifications if you want a confirmation prompt while the app is in the background. End tracking in the app when your trip is over. Location stays on your phone."),
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
                            Text(step.text).font(.subheadline).foregroundStyle(.secondary)
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
