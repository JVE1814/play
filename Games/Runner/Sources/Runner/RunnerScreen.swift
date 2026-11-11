import PlayKit
import RunnerEngine
import SwiftUI

struct RunnerScreen: View {
    @StateObject private var session: RunnerSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: GameContext) {
        _session = StateObject(wrappedValue: RunnerSession(context: context))
    }

    var body: some View {
        let paused = session.phase == .paused
        GameScreen(session: session) {
            RunnerReadouts(hud: session.hud, best: session.best)
        } table: {
            PierView(session: session, reduceMotion: reduceMotion, live: !session.context.options.disableAnimations)
                .padding(.horizontal, Theme.Space.s)
        } tools: {
            ToolbarButton(paused ? "Carry On" : "Pause", systemImage: paused ? "play.fill" : "pause.fill", identifier: "pause") {
                session.togglePause()
            }
            .disabled(session.phase != .running && !paused)
            ToolbarButton("New Run", systemImage: "arrow.counterclockwise", identifier: "newRun") {
                session.requestNewRun()
            }
        } result: {
            RunnerResult(session: session)
        }
        .confirmation("Start a new run?", isPresented: $session.confirmingNewRun,
                      message: "This run ends here, with the score it has.", confirm: "New Run") {
            session.startNewRun()
        }
    }
}

/// The numbers in the top bar. They follow the run many times a second, on their own.
struct RunnerReadouts: View {
    @ObservedObject var hud: RunnerHUD
    let best: Int

    var body: some View {
        HStack(spacing: Theme.Space.xl) {
            Readout("Score", value: hud.score.formatted(), identifier: "runnerScore")
            Readout("Coins", value: hud.coins.formatted(), identifier: "runnerCoins")
            Readout("Best", value: best.formatted(), label: "Best score", identifier: "runnerBest")
        }
    }
}

/// Shown when the run ends.
struct RunnerResult: View {
    @ObservedObject var session: RunnerSession

    var body: some View {
        ResultPanel(identifier: "runnerResult") {
            if let result = session.result {
                ResultHeadline(result.headline)
                HStack(spacing: Theme.Space.s) {
                    StatValue("Score", value: result.score.formatted())
                    StatValue("Metres", value: result.metres.formatted())
                    StatValue("Coins", value: result.coins.formatted())
                }
                ResultMessage(message(result))
                VStack(spacing: Theme.Space.s) {
                    Button("Run Again") { session.startNewRun() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("resultRunAgain")
                    Button("All Games") { session.leave() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("resultHome")
                }
            }
        }
    }

    private func message(_ result: RunnerSession.Result) -> String {
        if result.reachedGoal {
            return "That beats the goal of \(result.goal.formatted()). The next one is \(Goals.next(after: session.best).formatted())."
        }
        let short = "\((result.goal - result.score).formatted()) short of the goal of \(result.goal.formatted())."
        return result.isBest ? short : short + " Your best is \(session.best.formatted())."
    }
}
