import ArcheryEngine
import PlayKit
import SwiftUI

/// The Archery screen: top bar (level and score), the range, and a thumb-height toolbar.
struct ArcheryScreen: View {
    let context: GameContext
    @StateObject private var session: ArcherySession
    @ObservedObject private var preferences: ArcheryPreferences
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: GameContext) {
        self.context = context
        _session = StateObject(wrappedValue: ArcherySession(context: context))
        _preferences = ObservedObject(wrappedValue: ArcheryPreferences.shared(in: context))
    }

    private var animate: Bool { !reduceMotion && !context.options.disableAnimations }

    var body: some View {
        VStack(spacing: 0) {
            GameTopBar(onBack: { session.leave() }, onSettings: { context.openSettings() }) {
                ArcheryReadout(session: session)
            }
            if context.options.showBoardSignature {
                Text(session.signature)
                    .font(.system(size: 6))
                    .lineLimit(1)
                    .foregroundStyle(context.accent.onTable)
                    .accessibilityIdentifier("boardSignature")
            }
            RangeView(session: session, preferences: preferences, reduceMotion: reduceMotion)
                .padding(.horizontal, Theme.Space.s)
            toolbar
        }
        .background(context.accent.table.ignoresSafeArea())
        .overlay {
            if session.showsResult {
                ArcheryResultOverlay(session: session)
                    .transition(animate ? .opacity.combined(with: .scale(scale: 0.96)) : .opacity)
            }
        }
        .animation(animate ? .easeOut(duration: 0.25) : nil, value: session.showsResult)
        .environment(\.accent, context.accent)
        .sheet(isPresented: $session.showingLevels) {
            ArcheryLevelList(session: session)
                .environment(\.accent, context.accent)
        }
        .confirmationDialog("Restart this level?", isPresented: $session.confirmingRestart, titleVisibility: .visible) {
            Button("Restart", role: .destructive) { session.retry() }
            Button("Keep Playing") {}
        } message: {
            Text("Your arrows so far won't count.")
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
            ToolbarButton("Tip", systemImage: "lightbulb.fill", identifier: "tipButton") {
                session.showingTip.toggle()
            }
            .disabled(!session.isPlaying)
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

/// Level number and score, centred in the top bar.
struct ArcheryReadout: View {
    @ObservedObject var session: ArcherySession
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: Theme.Space.xl) {
            readout(value: "\(session.level.number)", title: "Level")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Level")
                .accessibilityValue("\(session.level.number) of \(LevelCatalog.count)")
                .accessibilityIdentifier("archeryLevel")
            readout(value: "\(session.displayedScore)", title: "Score")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Score")
                .accessibilityValue("\(session.displayedScore)")
                .accessibilityIdentifier("archeryScore")
            readout(value: "\(session.displayedArrowsLeft)", title: session.displayedArrowsLeft == 1 ? "Arrow" : "Arrows")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Arrows left")
                .accessibilityValue("\(session.displayedArrowsLeft)")
                .accessibilityIdentifier("arrowsLeft")
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
        .frame(minWidth: 48)
    }
}

/// Shown when every arrow is shot, or the time runs out.
struct ArcheryResultOverlay: View {
    @ObservedObject var session: ArcherySession

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

    private var round: ArcheryRound { session.round }

    private var title: String {
        if round.passed {
            return round.level.number == LevelCatalog.count ? "Champion!" : "Level \(round.level.number) complete"
        }
        return round.timedOut ? "Out of time" : "Not quite"
    }

    private var message: String? {
        if round.passed {
            guard round.stars < 3 else { return nil }
            return "\(round.level.starScores[round.stars]) points earns \(round.stars == 2 ? "three stars" : "two stars")."
        }
        let level = round.level
        let advice: String
        if level.layout.onePerSpot {
            advice = "One arrow in each spot."
        } else if level.motion.isMoving && level.wind.isCalm {
            advice = "Aim a little ahead of the moving target."
        } else if !level.wind.isCalm {
            advice = "Watch the flag, and aim into the wind."
        } else {
            advice = "Let go while the sight is steady."
        }
        return "\(level.starScores[0]) points earns a star. \(advice)"
    }

    private var panel: some View {
        VStack(spacing: Theme.Space.l) {
            StarRow(stars: round.stars, size: 34)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(round.stars) of 3 stars")
                .accessibilityIdentifier("resultStars")
            Text(title)
                .font(Typography.display)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 5) {
                ForEach(Array(round.shots.enumerated()), id: \.offset) { _, shot in
                    ScoreChip(hit: shot.hit, size: 32)
                }
                ForEach(0..<max(0, round.level.arrows - round.shots.count), id: \.self) { _ in
                    EmptyChip(size: 32)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Arrows: " + round.shots.map(\.hit.label).joined(separator: ", "))
            HStack(spacing: Theme.Space.s) {
                StatValue("Score", value: "\(round.score) of \(round.maxScore)")
                StatValue("X count", value: "\(round.xCount)")
                StatValue("Best", value: "\(session.progress.bestScore(for: round.level.number) ?? round.score)")
            }
            if let message {
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: Theme.Space.s) {
                if round.passed && session.hasNextLevel {
                    Button("Next Level") { session.nextLevel() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("archeryNext")
                    Button("Shoot Again") { session.retry() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("archeryReplay")
                } else {
                    Button(round.passed ? "Shoot Again" : "Try Again") { session.retry() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("archeryRetry")
                }
                Button("All Levels") { session.showingLevels = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("archeryLevels")
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("archeryResult")
    }
}

/// All 30 levels by venue, with stars and best scores. Passed and current levels can be shot;
/// the rest unlock one by one.
struct ArcheryLevelList: View {
    @ObservedObject var session: ArcherySession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let progress = session.progress
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("\(progress.totalStars) of \(LevelCatalog.count * 3) stars · \(LevelCatalog.count) levels")
                            .font(Typography.label)
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityIdentifier("levelSummary")
                        ForEach(Chapter.allCases) { chapter in
                            VStack(alignment: .leading, spacing: Theme.Space.s) {
                                ChapterHeader(chapter: chapter)
                                ForEach(LevelCatalog.all.filter { $0.chapter == chapter }) { level in
                                    LevelRow(level: level, unlocked: progress.isUnlocked(level.number),
                                             stars: progress.stars(for: level.number),
                                             best: progress.bestScore(for: level.number),
                                             current: level.number == session.level.number) {
                                        session.start(level: level.number)
                                        dismiss()
                                    }
                                    .id(level.number)
                                }
                            }
                        }
                    }
                    .padding(Theme.Space.l)
                }
                .onAppear { proxy.scrollTo(session.level.number, anchor: .center) }
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

/// A venue's name over a strip of its sky.
struct ChapterHeader: View {
    let chapter: Chapter

    var body: some View {
        let venue = Venue.of(chapter)
        HStack(spacing: Theme.Space.m) {
            RoundedRectangle(cornerRadius: Theme.Radius.s, style: .continuous)
                .fill(LinearGradient(colors: [venue.skyTop, venue.skyMiddle, venue.skyHorizon, venue.groundFar],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(Typography.title)
                    .foregroundStyle(Theme.ink)
                Text("\(chapter.timeOfDay) · levels \(chapter.levels.lowerBound)–\(chapter.levels.upperBound)")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.top, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct LevelRow: View {
    let level: Level
    let unlocked: Bool
    let stars: Int
    let best: Int?
    let current: Bool
    let action: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                ZStack {
                    Circle().fill(current ? accent.fill : (unlocked ? Theme.hairline : Theme.hairline.opacity(0.5)))
                    if unlocked {
                        Text("\(level.number)")
                            .font(Typography.headline)
                            .monospacedDigit()
                            .foregroundStyle(current ? accent.onFill : Theme.ink)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.name)
                        .font(Typography.headline)
                        .foregroundStyle(unlocked ? Theme.ink : Theme.inkSecondary)
                    Text(level.summary)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: Theme.Space.s)
                if unlocked {
                    VStack(alignment: .trailing, spacing: 3) {
                        StarRow(stars: stars, size: 14)
                        if let best {
                            Text("Best \(best)")
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
            .padding(Theme.Space.m)
            .frame(minHeight: Theme.minTouchTarget + 12)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .strokeBorder(current ? accent.fill : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(level.number), \(level.name)")
        .accessibilityValue(value)
        .accessibilityHint(unlocked ? level.summary : "Pass the level before it to unlock.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("level-\(level.number)")
    }

    private var value: String {
        guard unlocked else { return "Locked" }
        var text = "\(stars) of 3 stars"
        if let best { text += ", best \(best)" }
        if current { text += ", current" }
        return text
    }
}
