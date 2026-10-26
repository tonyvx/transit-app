import SwiftUI

struct HelpAndFeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("How to use") {
                    NavigationLink("Open the guide") {
                        HowToView(embedded: true)
                    }
                }

                Section("Feedback") {
                    if let url = feedbackURL(
                        subject: "Boston Transit bug report",
                        body: "What happened?\n\nWhat did you expect?\n\nSteps to reproduce:\n\nPlease avoid including personal or precise location information."
                    ) {
                        Link(destination: url) {
                            Label("Report a bug", systemImage: "ladybug")
                        }
                        .accessibilityIdentifier("reportBugLink")
                    }
                    if let url = feedbackURL(
                        subject: "Boston Transit feature request",
                        body: "What would you like the app to do?\n\nHow would it help your transit trip?\n\nPlease avoid including personal or precise location information."
                    ) {
                        Link(destination: url) {
                            Label("Request a feature", systemImage: "lightbulb")
                        }
                        .accessibilityIdentifier("requestFeatureLink")
                    }
                    Text("Opens your email app to send feedback to valantra.app@gmail.com.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Terms and privacy") {
                    Text("Boston Transit is an independent app, not affiliated with or endorsed by the MBTA. Transit data is provided by the MBTA through its V3 API and is subject to MBTA terms and availability.")
                    if let url = URL(string: "https://www.mbta.com/developers") {
                        Link("MBTA developer information", destination: url)
                    }
                    Text("Location is processed on this iPhone to show your position, find nearby stations, match you to a train and plan trips. If you opt in to background trip updates, GPS runs only during a trip you confirm. Location is not sent to the app developer or stored on a server.")
                    Text("Address searches and walking or driving directions are handled by Apple Maps and may include the places or coordinates you search for or route between. The app has no account, analytics, advertising or tracking.")
                    Text("Trip planner times use live MBTA predictions when available and schedules otherwise. Bike and scooter times are estimates. Reminders are local notifications and do not react to service delays.")
                    Text("Contact: valantra.app@gmail.com")
                }
                .font(.footnote)
            }
            .navigationTitle("Help & feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func feedbackURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "valantra.app@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
