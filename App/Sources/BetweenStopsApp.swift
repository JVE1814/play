import PlayKit
import SwiftUI

@main
struct BetweenStopsApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.stats)
        }
    }
}
