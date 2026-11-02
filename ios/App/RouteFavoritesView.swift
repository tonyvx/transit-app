import SwiftUI

struct FavoriteLinesEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(LineGroup.allCases.filter { !model.routes(in: $0).isEmpty }) { line in
                lineSection(line)
            }
        }
        .navigationTitle("Favorite lines")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lineSection(_ line: LineGroup) -> some View {
        Section(line == .commuter ? "Commuter Rail" : "\(line.rawValue) Line") {
            ForEach(model.routes(in: line)) { route in
                Toggle(route.name, isOn: Binding(
                    get: { model.isFavoriteRoute(route.id) },
                    set: { _ in model.toggleFavoriteRoute(route.id) }
                ))
                ForEach(model.branches(for: route.id)) { branch in
                    Toggle(branch.name, isOn: Binding(
                        get: { model.isFavoriteBranch(branch) },
                        set: { _ in model.toggleFavoriteBranch(branch) }
                    ))
                    .padding(.leading, 20)
                    .font(.subheadline)
                }
            }
        }
    }
}
