import SwiftUI

/// Shown while no lines are chosen (a fresh install), so the map isn't just empty.
struct FirstRunCard: View {
    @Environment(AppModel.self) private var model
    @State private var picked: Set<LineGroup> = []
    let onHowTo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which lines do you ride?").font(.headline)
            Text("Pick one or more to see their trains and stations. You can change this later in Preferences.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LineGroup.allCases) { line in
                        let on = picked.contains(line)
                        Button {
                            if on { picked.remove(line) } else { picked.insert(line) }
                        } label: {
                            Text(line.rawValue)
                                .font(.footnote.bold())
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(on ? line.color : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(line.color, lineWidth: 2))
                                .foregroundStyle(on ? .white : line.color)
                        }
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            HStack {
                Button("Show trains") {
                    var p = model.preferences
                    p.lines = picked
                    model.savePreferences(p)
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked.isEmpty)
                Button("How to use", action: onHowTo).buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
