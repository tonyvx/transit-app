import SwiftUI

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let route: RouteInfo
    let color: Color
    let directions: [RouteDirection]
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Direction.allCases) { direction in
                    Section(direction.label) {
                        let routes = directions.filter { $0.direction == direction }
                        if routes.isEmpty {
                            Text("Direction details are unavailable.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(routes) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Start: \(item.startStop)")
                                            .font(.subheadline)
                                        Text("End: \(item.endStop)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(route.name)
                        .font(.custom("HelveticaNeue-Bold", size: 20))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(color, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .secondary)
                    }
                    .accessibilityLabel(isFavorite ? "Remove \(route.name) from favorites" : "Favorite \(route.name)")
                    .accessibilityIdentifier("favoriteRouteButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
