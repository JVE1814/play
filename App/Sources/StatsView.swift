import PlayKit
import SwiftUI

/// Statistics for every game, from the shared store.
struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var stats: StatsStore
    @Environment(\.dismiss) private var dismiss
    @State private var resetCandidate: RegisteredGame?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.l) {
                    ForEach(model.games) { game in
                        StatsPanel(game: game, stats: stats.stats(for: game.id)) {
                            resetCandidate = game
                        }
                    }
                }
                .padding(Theme.Space.l)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Typography.headline)
                        .accessibilityIdentifier("done")
                }
            }
            .alert("Reset statistics?", isPresented: Binding(
                get: { resetCandidate != nil },
                set: { if !$0 { resetCandidate = nil } }
            )) {
                Button("Reset", role: .destructive) {
                    if let game = resetCandidate { stats.reset(gameID: game.id) }
                    resetCandidate = nil
                }
                Button("Cancel", role: .cancel) { resetCandidate = nil }
            } message: {
                Text("This clears wins, streaks and best times for \(resetCandidate?.module.title ?? "this game").")
            }
        }
    }
}

struct StatsPanel: View {
    let game: RegisteredGame
    let stats: GameStats
    let onReset: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let accent = game.module.accent
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                Circle()
                    .fill(accent.fill)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(game.module.title)
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            LazyVGrid(columns: columns, spacing: Theme.Space.l) {
                StatValue("Played", value: "\(stats.played)")
                StatValue("Won", value: "\(stats.won)")
                StatValue("Win rate", value: Format.percent(stats.winRate))
                StatValue("Best time", value: stats.bestTime.map(Format.clock) ?? "–")
                StatValue("Current streak", value: "\(stats.currentStreak)")
                StatValue("Best streak", value: "\(stats.bestStreak)")
            }
            .accessibilityIdentifier("stats-\(game.id)")
            Button("Reset Statistics", role: .destructive, action: onReset)
                .font(Typography.label)
                .foregroundStyle(Theme.danger)
                .frame(minHeight: Theme.minTouchTarget)
                .disabled(stats.played == 0)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous).fill(Theme.surface))
    }
}
