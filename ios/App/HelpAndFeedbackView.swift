import SwiftUI

struct TermsPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Terms & Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
