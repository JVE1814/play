import BubbleEngine
import PlayKit
import SwiftUI

/// The Bubbles screen: top bar (level and shots), the field, and a thumb-height toolbar.
struct BubblesScreen: View {
    let context: GameContext
    @StateObject private var session: BubblesSession
    @ObservedObject private var preferences: BubblesPreferences
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: GameContext) {
        self.context = context
        _session = StateObject(wrappedValue: BubblesSession(context: context))
        _preferences = ObservedObject(wrappedValue: BubblesPreferences.shared(in: context))
    }

    private var animate: Bool { !reduceMotion && !context.options.disableAnimations }

    var body: some View {
        VStack(spacing: 0) {
            GameTopBar(onBack: { session.leave() }, onSettings: { context.openSettings() }) {
                BubblesReadout(session: session)
            }
            if context.options.showBoardSignature {
                Text(session.signature)
                    .font(.system(size: 6))
                    .lineLimit(1)
                    .foregroundStyle(context.accent.onTable)
                    .accessibilityIdentifier("boardSignature")
            }
            GeometryReader { proxy in
                FieldView(session: session, preferences: preferences, layout: FieldLayout(size: proxy.size),
                          animate: animate)
            }
            toolbar
        }
        .background(context.accent.table.ignoresSafeArea())
        .overlay {
            if session.showsResult {
                BubblesResultOverlay(session: session)
                    .transition(animate ? .opacity.combined(with: .scale(scale: 0.96)) : .opacity)
            }
        }
        .animation(animate ? .easeOut(duration: 0.25) : nil, value: session.showsResult)
        .environment(\.accent, context.accent)
        .sheet(isPresented: $session.showingLevels) {
            LevelListView(session: session)
                .environment(\.accent, context.accent)
        }
        .confirmationDialog("Restart this level?", isPresented: $session.confirmingRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { session.retry() }
            Button("Keep Playing") {}
        } message: {
            Text("You'll start again with a fresh set of bubbles.")
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
            ToolbarButton("Levels", systemImage: "square.grid.3x3.fill", identifier: "levels") {
                session.showingLevels = true
            }
            ToolbarButton("Swap", systemImage: "arrow.left.arrow.right", identifier: "swap") { session.swap() }
                .disabled(!session.isPlaying || session.game.current == session.game.next)
            ToolbarButton("Restart", systemImage: "arrow.counterclockwise", identifier: "restart") {
                session.requestRestart()
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.xs)
        .padding(.bottom, Theme.Space.s)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Level number and shots left, centred in the top bar.
struct BubblesReadout: View {
    @ObservedObject var session: BubblesSession
    @Environment(\.accent) private var accent

    var body: some View {
        let game = session.game
        HStack(spacing: Theme.Space.xl) {
            readout(value: "\(game.levelNumber)", title: "Level")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Level")
                .accessibilityValue("\(game.levelNumber) of \(LevelCatalog.count)")
                .accessibilityIdentifier("bubbleLevel")
            let low = game.shotsLeft <= 3 && game.status == .playing
            readout(value: "\(game.shotsLeft)", title: game.shotsLeft == 1 ? "Shot" : "Shots")
                .foregroundStyle(low ? Theme.onHighlight : accent.onTable)
                .padding(.horizontal, low ? Theme.Space.s : 0)
                .background(Capsule().fill(low ? Theme.highlight : Color.clear))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Shots left")
                .accessibilityValue("\(game.shotsLeft)")
                .accessibilityIdentifier("shotsLeft")
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

/// Shown when a level is cleared or lost.
struct BubblesResultOverlay: View {
    @ObservedObject var session: BubblesSession

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

    private var won: Bool { session.game.status == .won }

    private var title: String {
        switch session.game.status {
        case .won: return "Level \(session.game.levelNumber) cleared!"
        case .reachedLine: return "Too close to the line"
        case .outOfShots, .playing: return "Out of shots"
        }
    }

    private var panel: some View {
        let game = session.game
        return VStack(spacing: Theme.Space.l) {
            if won {
                StarRow(stars: game.stars, size: 34)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(game.stars) of 3 stars")
                    .accessibilityIdentifier("resultStars")
            }
            Text(title)
                .font(Typography.display)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            if won {
                HStack(spacing: Theme.Space.s) {
                    StatValue("Shots used", value: "\(game.shotsFired)")
                    StatValue("Par", value: "\(game.par)")
                    StatValue("Total stars", value: "\(session.progress.totalStars)")
                }
            } else {
                Text(game.status == .reachedLine
                     ? "A bubble ended up below the dashed line. Try again with a fresh set of bubbles."
                     : "\(game.grid.count) bubble\(game.grid.count == 1 ? "" : "s") left. Try again with a fresh set of bubbles.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Theme.Space.s) {
                if won && session.hasNextLevel {
                    Button("Next Level") { session.nextLevel() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("bubblesNext")
                    Button("Replay Level") { session.retry() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("bubblesReplay")
                } else {
                    Button("Try Again") { session.retry() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("bubblesRetry")
                }
                Button("All Levels") { session.showingLevels = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("bubblesLevels")
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bubblesResult")
    }
}

/// Three stars, filled for those earned.
struct StarRow: View {
    let stars: Int
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(0..<3, id: \.self) { index in
                BubbleSymbol(kind: .star)
                    .fill(index < stars ? Theme.highlight : Theme.hairline)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// All 2,000 levels with their stars. Cleared and current levels can be played; the rest unlock
/// one by one.
struct LevelListView: View {
    @ObservedObject var session: BubblesSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let progress = session.progress
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.s),
                            count: dynamicTypeSize.isAccessibilitySize ? 3 : 5)
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("\(progress.totalStars) of \(LevelCatalog.count * 3) stars · \(LevelCatalog.count.formatted()) levels")
                            .font(Typography.label)
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityIdentifier("levelSummary")
                        LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                            ForEach(1...LevelCatalog.count, id: \.self) { level in
                                LevelCell(level: level, unlocked: progress.isUnlocked(level),
                                          stars: progress.stars(for: level), current: level == session.level) {
                                    session.start(level: level)
                                    dismiss()
                                }
                                .id(level)
                            }
                        }
                    }
                    .padding(Theme.Space.l)
                }
                .onAppear { proxy.scrollTo(max(1, session.level), anchor: .center) }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Levels")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Typography.headline)
                        .accessibilityIdentifier("done")
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
        .accessibilityValue(unlocked ? "\(stars) of 3 stars\(current ? ", current" : "")" : "Locked")
        .accessibilityIdentifier("level-\(level)")
    }
}
