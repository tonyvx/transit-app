import ActivityKit
import SwiftUI
import WidgetKit

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "tram.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(context.state.routeName).font(.headline)
                        Spacer()
                        Text("\(context.state.stopsRemaining) left")
                            .font(.caption.bold())
                            .monospacedDigit()
                    }
                    Text("Next: \(context.state.nextStop)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack {
                        Text("To \(context.state.destination)").lineLimit(1)
                        Spacer()
                        Text(context.isStale ? "Update delayed" : context.state.status)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "tram.fill").foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.stopsRemaining) stops")
                        .font(.caption.bold())
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next: \(context.state.nextStop)").font(.headline).lineLimit(1)
                        Text("To \(context.state.destination) · \(context.state.status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
            } compactTrailing: {
                Text("\(context.state.stopsRemaining)")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "tram.fill")
            }
        }
    }
}
