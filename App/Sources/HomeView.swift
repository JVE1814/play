import PlayKit
import SwiftUI

/// Lists every registered game. It knows nothing about any particular game.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var stats: StatsStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Between Stops")
                        .font(Typography.display)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("homeTitle")
                    Text("Quick games for the ride. Everything stays on your phone.")
                        .font(Typography.body)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(.bottom, Theme.Space.s)
                ForEach(model.games) { game in
                    GameTile(game: game, status: game.module.statusLine(context: model.context(for: game))) {
                        model.open(game)
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.xl)
            .padding(.bottom, Theme.Space.l)
        }
        .safeAreaInset(edge: .bottom) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Theme.Space.s))
                : AnyLayout(HStackLayout(spacing: Theme.Space.m))
            layout {
                HomeButton(title: "Statistics", systemImage: "chart.bar.fill", identifier: "statsButton") {
                    model.showingStats = true
                }
                HomeButton(title: "Settings", systemImage: "gearshape.fill", identifier: "settingsButton") {
                    model.showingSettings = true
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.s)
            .background(Theme.background)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// One big, colourful tile per game.
struct GameTile: View {
    let game: RegisteredGame
    let status: String?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let accent = game.module.accent
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.m))
            : AnyLayout(HStackLayout(spacing: Theme.Space.l))
        Button(action: action) {
            layout {
                game.module.makeIcon()
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(game.module.title)
                        .font(Typography.title)
                    Text(game.module.tagline)
                        .font(Typography.body)
                        .opacity(0.85)
                    if let status {
                        Text(status)
                            .font(Typography.label)
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, Theme.Space.xs)
                            .background(Capsule().fill(Color.white.opacity(0.35)))
                            .padding(.top, Theme.Space.xs)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(accent.onFill)
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous).fill(accent.fill))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(game.module.title)
        .accessibilityValue(status ?? game.module.tagline)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("game-\(game.id)")
    }
}

/// A wide button in the home screen's bottom bar, within thumb reach.
struct HomeButton: View {
    let title: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Typography.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(Theme.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
