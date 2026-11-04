import KlondikeEngine
import PlayKit
import SwiftUI

/// The Solitaire screen: top bar (moves and time), the table, and a thumb-height toolbar.
struct SolitaireScreen: View {
    let context: GameContext
    @StateObject private var session: SolitaireSession
    @ObservedObject private var preferences: SolitairePreferences
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: GameContext) {
        self.context = context
        _session = StateObject(wrappedValue: SolitaireSession(context: context))
        _preferences = ObservedObject(wrappedValue: SolitairePreferences.shared(in: context))
    }

    private var animate: Bool { !reduceMotion && !context.options.disableAnimations }

    var body: some View {
        VStack(spacing: 0) {
            GameTopBar(onBack: { session.leave() }, onSettings: { context.openSettings() }) {
                StatusReadout(session: session)
            }
            if context.options.showBoardSignature {
                Text(session.signature)
                    .font(.system(size: 6))
                    .lineLimit(1)
                    .foregroundStyle(context.accent.onTable)
                    .accessibilityIdentifier("boardSignature")
            }
            GeometryReader { proxy in
                BoardView(session: session,
                          layout: BoardLayout(size: proxy.size, leftHanded: preferences.leftHanded),
                          animate: animate)
            }
            toolbar
        }
        .background(context.accent.table.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let toast = session.toast {
                Toast(toast)
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.bottom, 96)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if session.showsWin {
                WinOverlay(time: session.elapsed(), moves: session.game.moveCount,
                           stats: context.gameStats,
                           onNewGame: { session.startNewGame() },
                           onHome: { session.leave() })
                    .transition(animate ? .opacity.combined(with: .scale(scale: 0.96)) : .opacity)
            }
        }
        .animation(animate ? .easeOut(duration: 0.25) : nil, value: session.showsWin)
        .animation(animate ? .easeOut(duration: 0.2) : nil, value: session.toast)
        .environment(\.accent, context.accent)
        .confirmationDialog("Start a new deal?", isPresented: $session.confirmingNewGame, titleVisibility: .visible) {
            Button("New Deal", role: .destructive) { session.startNewGame() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("The current game will count as a loss.")
        }
        .onAppear {
            session.animationsEnabled = animate
            session.setOnScreen(scenePhase == .active)
        }
        .onDisappear { session.setOnScreen(false) }
        .onChange(of: scenePhase) { _, phase in session.setOnScreen(phase == .active) }
        .onChange(of: reduceMotion) { _, _ in session.animationsEnabled = animate }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Space.s) {
            if preferences.leftHanded {
                undoButton
                middleButton
                newButton
            } else {
                newButton
                middleButton
                undoButton
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.xs)
        .padding(.bottom, Theme.Space.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
                .disabled(!session.canHint)
        }
    }

    private var undoButton: some View {
        ToolbarButton("Undo", systemImage: "arrow.uturn.backward", identifier: "undo") { session.undo() }
            .disabled(!session.canUndo)
    }
}

/// Moves and elapsed time, centred in the top bar.
struct StatusReadout: View {
    @ObservedObject var session: SolitaireSession
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Theme.Space.xl) {
            readout(value: "\(session.game.moveCount)", title: "Moves")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Moves")
                .accessibilityValue("\(session.game.moveCount)")
                .accessibilityIdentifier("moves")
            TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                let seconds = session.elapsed(at: timeline.date)
                readout(value: Format.clock(seconds), title: "Time")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Time")
                    .accessibilityValue(Format.spokenDuration(seconds))
                    .accessibilityIdentifier("timer")
            }
        }
        .foregroundStyle(accent.onTable)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func readout(value: String, title: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Typography.numeric)
                .lineLimit(1)
            Text(title)
                .font(Typography.caption)
                .opacity(0.8)
        }
        .frame(minWidth: 56)
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
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                panel
                ScrollView { panel }
            }
            .padding(Theme.Space.l)
        }
    }

    private var panel: some View {
        VStack(spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.s) {
                ForEach([Suit.spades, .hearts, .clubs, .diamonds], id: \.self) { suit in
                    SuitShape(suit: suit)
                        .fill(suit.isRed ? CardPalette.red : CardPalette.black)
                        .frame(width: 26, height: 26)
                }
            }
            .accessibilityHidden(true)
            Text("You won!")
                .font(Typography.display)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
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
        .padding(Theme.Space.xl)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("winScreen")
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
