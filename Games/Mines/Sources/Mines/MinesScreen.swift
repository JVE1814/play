import MinesEngine
import PlayKit
import SwiftUI

/// The Mines screen: mines left and time in the top bar, the board, and New and Flag in the
/// toolbar.
struct MinesScreen: View {
    @StateObject private var session: MinesSession
    @ObservedObject private var preferences: MinesPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: GameContext) {
        _session = StateObject(wrappedValue: MinesSession(context: context))
        _preferences = ObservedObject(wrappedValue: context.preferences(MinesPreferences.self))
    }

    var body: some View {
        let animate = session.context.animates(reduceMotion: reduceMotion)
        GameScreen(session: session) {
            Readout("Mines", value: "\(session.game.minesLeft)", label: "Mines left", identifier: "minesLeft")
            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                let seconds = session.elapsed(at: timeline.date)
                Readout("Time", value: Format.clock(seconds), spokenValue: Format.spokenDuration(seconds),
                        identifier: "minesTime")
            }
        } table: {
            GeometryReader { proxy in
                let layout = MinesLayout(size: proxy.size)
                ZStack(alignment: .top) {
                    MinesBoardView(session: session, layout: layout, animate: animate)
                    if let toast = session.toast {
                        Toast(toast)
                            .padding(.horizontal, Theme.Space.l)
                            .padding(.top, max(Theme.Space.m, layout.origin.y - 56))
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
            }
            .animation(animate ? .easeOut(duration: 0.2) : nil, value: session.toast)
        } tools: {
            if preferences.leftHanded {
                flagButton
                newButton
            } else {
                newButton
                flagButton
            }
        } result: {
            MinesResultView(session: session)
        }
        .confirmation("Start a new board?", isPresented: $session.confirmingNewBoard,
                      message: "This board will count as a loss.", confirm: "New Board") {
            session.startNewBoard()
        }
    }

    private var newButton: some View {
        ToolbarButton("New", systemImage: "plus", identifier: "newBoard") { session.requestNewBoard() }
    }

    private var flagButton: some View {
        ToolbarButton("Flag", systemImage: session.flagMode ? "flag.fill" : "flag", identifier: "minesFlag",
                      isOn: session.flagMode) {
            session.toggleFlagMode()
        }
        .disabled(session.game.isFinished)
    }
}

/// The slip question, or the result once the board is over.
struct MinesResultView: View {
    @ObservedObject var session: MinesSession

    var body: some View {
        let game = session.game
        switch game.status {
        case .slipped:
            ResultPanel(identifier: "minesSlipPanel", alignment: clearOfMine) {
                ResultHeadline("That was a mine")
                ResultMessage("You get one take-back per board.")
                VStack(spacing: Theme.Space.s) {
                    Button("Take It Back") { session.takeBack() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("slipTakeBack")
                    Button("End Board") { session.endBoard() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("slipEndBoard")
                }
            }
        case .won, .lost:
            ResultPanel(identifier: "minesResult", alignment: clearOfMine) {
                ResultHeadline(game.status == .won ? "Board cleared!" : "Board lost")
                stats(game)
                ResultMessage(message(game))
                VStack(spacing: Theme.Space.s) {
                    Button("New Board") { session.startNewBoard() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("resultNewBoard")
                    Button("See the Board") { session.seeBoard() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("resultSeeBoard")
                    Button("All Games") { session.leave() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("resultHome")
                }
            }
        case .fresh, .playing:
            EmptyView()
        }
    }

    /// Panels move to the half of the screen away from the opened mine, so it stays in view.
    private var clearOfMine: Alignment {
        guard let mine = session.game.exploded else { return .center }
        return MinesGrid.row(of: mine) < MinesGrid.rows / 2 ? .bottom : .top
    }

    @ViewBuilder private func stats(_ game: MinesGame) -> some View {
        let time = session.elapsed()
        if game.status == .won {
            HStack(spacing: Theme.Space.s) {
                StatValue("Time", value: Format.clock(time))
                StatValue("Best on \(game.difficulty.name)",
                          value: session.bestTimes[game.difficulty].map(Format.clock) ?? "–")
                StatValue("Streak", value: "\(session.context.gameStats.currentStreak)")
            }
        } else {
            HStack(spacing: Theme.Space.s) {
                StatValue("Cleared", value: "\(game.opened.count) of \(game.safeCount)")
                StatValue("Time", value: Format.clock(time))
                StatValue("Win rate", value: Format.percent(session.context.gameStats.winRate))
            }
        }
    }

    private func message(_ game: MinesGame) -> String {
        if game.status == .lost { return "Every board can be solved without guessing." }
        if session.isNewBest { return "A new best for \(game.difficulty.name)." }
        return "\(game.difficulty.name), \(Format.count(game.difficulty.mineCount, "mine"))."
    }
}
