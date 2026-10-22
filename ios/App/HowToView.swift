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
             text: "Tap the gear. Turn on the lines you ride, then optionally pick specific routes or branches. Choose Inbound or Outbound, and Save. Only the lines you pick appear as chips on the map."),
        Step(id: "map", image: "howto-map", title: "2. Watch trains on the map",
             text: "Tap a chip to show or hide a line for now. Tap a train to see its status. Trains that have already passed you are hidden unless you turn that off in Preferences."),
        Step(id: "station", image: "howto-station", title: "3. Check a station",
             text: "Tap a station dot to see arrival times by train number. Tap a train number to close the sheet and highlight that train on the map with a halo."),
        Step(id: "alerts", image: "howto-alerts", title: "4. Read alerts",
             text: "Tap the alert count. Alerts for your lines come first. Lines that start ahead of you show the drive time to get there. Other lines are collapsed."),
        Step(id: "planner", image: "howto-planner", title: "5. Plan a trip",
             text: "Tap the route icon. Search an address, use your location, or drop a pin on the map. Pick how you get to and from the station (walk, bike, scooter or car), then Find trips. Tap a result to draw it on the map. Times are scheduled, not live."),
    ]

    var body: some View {
        if embedded { content } else { NavigationStack { content.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } } }
    }

    private var content: some View {
            ScrollView {
                VStack(spacing: 28) {
                    Text("Your location stays on your phone. Transit data comes from the MBTA.")
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
