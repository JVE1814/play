import KlondikeEngine
import PlayKit
import SwiftUI

/// The Solitaire screen: moves and time in the top bar, the table, and New, Hint or Finish, and
/// Undo in the toolbar.
struct SolitaireScreen: View {
    @StateObject private var session: SolitaireSession
    @ObservedObject private var preferences: SolitairePreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: GameContext) {
        _session = StateObject(wrappedValue: SolitaireSession(context: context))
        _preferences = ObservedObject(wrappedValue: context.preferences(SolitairePreferences.self))
    }

    var body: some View {
        let animate = session.context.animates(reduceMotion: reduceMotion)
        GameScreen(session: session) {
            Readout("Moves", value: "\(session.game.moveCount)", identifier: "moves")
            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                let seconds = session.elapsed(at: timeline.date)
                Readout("Time", value: Format.clock(seconds), spokenValue: Format.spokenDuration(seconds),
                        identifier: "timer")
            }
        } table: {
            GeometryReader { proxy in
                let layout = BoardLayout(size: proxy.size, leftHanded: preferences.leftHanded)
                ZStack(alignment: .bottom) {
                    BoardView(session: session, layout: layout, animate: animate)
                    if let toast = session.toast {
                        Toast(toast)
                            .padding(.horizontal, Theme.Space.l)
                            .padding(.bottom, layout.bottomRowHeight + Theme.Space.m)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
            }
            .animation(animate ? .easeOut(duration: 0.2) : nil, value: session.toast)
        } tools: {
            if preferences.leftHanded {
                undoButton
                middleButton
                newButton
            } else {
                newButton
                middleButton
                undoButton
            }
        } result: {
            WinOverlay(time: session.elapsed(), moves: session.game.moveCount,
                       stats: session.context.gameStats,
                       onNewGame: { session.startNewGame() },
                       onHome: { session.leave() })
        }
        .confirmation("Start a new deal?", isPresented: $session.confirmingNewGame,
                      message: "The current game will count as a loss.", confirm: "New Deal") {
            session.startNewGame()
        }
    }

    private var newButton: some View {
        ToolbarButton("New", systemImage: "plus", identifier: "newGame") { session.requestNewGame() }
            .disabled(session.isAutoFinishing)
    }

    @ViewBuilder private var middleButton: some View {
        if session.canAutoFinish {
            ToolbarButton("Finish", systemImage: "wand.and.stars", identifier: "autoFinish", prominent: true) {
                session.autoFinish()
            }
        } else {
            ToolbarButton("Hint", systemImage: "lightbulb.fill", identifier: "hint") { session.showHint() }
                .disabled(!session.canPlay)
        }
    }

    private var undoButton: some View {
        ToolbarButton("Undo", systemImage: "arrow.uturn.backward", identifier: "undo") { session.undo() }
            .disabled(!session.canUndo)
    }
}

/// Shown when the last card reaches the foundations.
struct WinOverlay: View {
    let time: TimeInterval
    let moves: Int
    let stats: GameStats
    let onNewGame: () -> Void
    let onHome: () -> Void

    var body: some View {
        ResultPanel(identifier: "winScreen") {
            HStack(spacing: Theme.Space.s) {
                ForEach([Suit.spades, .hearts, .clubs, .diamonds], id: \.self) { suit in
                    SuitShape(suit: suit)
                        .fill(suit.isRed ? CardPalette.red : CardPalette.black)
                        .frame(width: 26, height: 26)
                }
            }
            .accessibilityHidden(true)
            ResultHeadline("You won!")
            HStack(spacing: Theme.Space.s) {
                StatValue("Time", value: Format.clock(time))
                StatValue("Moves", value: "\(moves)")
                StatValue("Win rate", value: Format.percent(stats.winRate))
            }
            HStack(spacing: Theme.Space.s) {
                StatValue("Streak", value: "\(stats.currentStreak)")
                StatValue("Best time", value: stats.bestTime.map(Format.clock) ?? "–")
                StatValue("Wins", value: "\(stats.won)")
            }
            VStack(spacing: Theme.Space.s) {
                Button("New Deal", action: onNewGame)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("winNewGame")
                Button("Back to Games", action: onHome)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("winHome")
            }
        }
    }
}

/// Rows shown in the shared Settings screen.
struct SolitaireSettingsRows: View {
    @ObservedObject var preferences: SolitairePreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rows
        }
    }

    @ViewBuilder private var rows: some View {
        SettingsChoiceRow("Cards per draw",
                          detail: "Changes apply from your next deal.",
                          choices: DrawMode.allCases.map { (value: $0, label: $0.title) },
                          selection: $preferences.drawMode,
                          identifier: "drawMode")
        SettingsDivider()
        SettingsToggleRow("Left-handed layout",
                          detail: "Puts the stock and Undo on the left.",
                          isOn: $preferences.leftHanded,
                          identifier: "leftHanded")
    }
}
