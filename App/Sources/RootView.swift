import PlayKit
import SwiftUI

/// Shows the home screen, or the open game full screen.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let game = model.openGame {
                game.module.makeGameView(context: model.context(for: game))
                    .id(game.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            } else {
                HomeView()
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .animation(model.options.disableAnimations ? nil : .easeInOut(duration: 0.25), value: model.openGameID)
        .preferredColorScheme(model.colorScheme)
        .sheet(isPresented: $model.showingSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(model.stats)
                .preferredColorScheme(model.colorScheme)
        }
        .sheet(isPresented: $model.showingStats) {
            StatsView()
                .environmentObject(model)
                .environmentObject(model.stats)
                .preferredColorScheme(model.colorScheme)
        }
    }
}
