import SwiftUI

@main
struct TransitApp: App {
    @State private var model = AppModel()

    init() { Notifier.install() }

    var body: some Scene {
        WindowGroup { ContentView().environment(model) }
    }
}
