import BubbleEngine
import PlayKit
import SwiftUI

/// The Bubbles screen: level and shots in the top bar, the field, and Levels, Swap and Restart
/// in the toolbar.
struct BubblesScreen: View {
    @StateObject private var session: BubblesSession
    private let preferences: BubblesPreferences

    init(context: GameContext) {
        _session = StateObject(wrappedValue: BubblesSession(context: context))
        preferences = context.preferences(BubblesPreferences.self)
    }

    var body: some View {
        let game = session.game
        let lowOnShots = game.shotsLeft <= 3 && game.status == .playing
        GameScreen(session: session, obscured: session.showingLevels) {
            Readout("Level", value: "\(game.levelNumber)",
                    spokenValue: "\(game.levelNumber) of \(LevelCatalog.count.formatted())", identifier: "bubbleLevel")
            Readout(Format.plural(game.shotsLeft, "Shot"), value: "\(game.shotsLeft)", label: "Shots left",
                    identifier: "shotsLeft")
                .foregroundStyle(lowOnShots ? Theme.onHighlight : session.context.accent.onTable)
                .padding(.horizontal, lowOnShots ? Theme.Space.s : 0)
                .background(Capsule().fill(lowOnShots ? Theme.highlight : Color.clear))
        } table: {
            GeometryReader { proxy in
                FieldView(session: session, preferences: preferences, layout: FieldLayout(size: proxy.size))
            }
        } tools: {
            LevelsButton(session)
            ToolbarButton("Swap", systemImage: "arrow.left.arrow.right", identifier: "swap") { session.swap() }
                .disabled(!session.canSwap)
            RestartButton(session)
        } result: {
            BubblesResult(session: session)
        }
        .levelChrome(session, restartMessage: "You'll start again with a fresh set of bubbles.") {
            BubblesLevelList(session: session)
        }
    }
}

/// Shown when a level is cleared or lost.
struct BubblesResult: View {
    @ObservedObject var session: BubblesSession

    var body: some View {
        let game = session.game
        let won = game.status == .won
        let ending = game.ending
        ResultPanel(identifier: "bubblesResult") {
            if won { ResultStars(game.stars) }
            ResultHeadline(ending.title)
            if let message = ending.message {
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            } else {
                HStack(spacing: Theme.Space.s) {
                    StatValue("Shots used", value: "\(game.shotsFired)")
                    StatValue("Par", value: "\(game.par)")
                    StatValue("Total stars", value: "\(session.progress.totalStars)")
                }
            }
            LevelResultButtons(session, passed: won, replayTitle: "Replay Level")
        }
    }
}

/// Every level with its stars. Cleared and current levels can be played; the rest unlock one
/// by one.
struct BubblesLevelList: View {
    @ObservedObject var session: BubblesSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let progress = session.progress
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s),
                            count: dynamicTypeSize.isAccessibilitySize ? 3 : 5)
        LevelsSheet(session) {
            LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                ForEach(1...LevelCatalog.count, id: \.self) { level in
                    LevelCell(level: level, unlocked: progress.isUnlocked(level), stars: progress.stars(for: level),
                              current: level == session.levelNumber,
                              spokenState: progress.spokenState(of: level, isCurrent: level == session.levelNumber)) {
                        session.start(level: level)
                    }
                    .id(level)
                }
            }
        }
    }
}

struct LevelCell: View {
    let level: Int
    let unlocked: Bool
    let stars: Int
    let current: Bool
    let spokenState: String
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if unlocked {
                    Text("\(level)")
                        .font(Typography.headline)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    StarRow(stars: stars, size: 10)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("\(level)")
                        .font(Typography.caption)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(unlocked ? (current ? accent.onFill : Theme.ink) : Theme.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget + 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(current ? accent.fill : (unlocked ? Theme.surface : Theme.hairline))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityLabel("Level \(level)")
        .accessibilityValue(spokenState)
        .accessibilityIdentifier("level-\(level)")
    }
}
