import ArcheryEngine
import PlayKit
import SwiftUI

struct ArcheryScreen: View {
    @StateObject private var session: ArcherySession
    private let preferences: ArcheryPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(context: GameContext) {
        _session = StateObject(wrappedValue: ArcherySession(context: context))
        preferences = context.preferences(ArcheryPreferences.self)
    }

    var body: some View {
        GameScreen(session: session, obscured: session.showingLevels) {
            Readout("Level", value: "\(session.levelNumber)",
                    spokenValue: "\(session.levelNumber) of \(LevelCatalog.count)", identifier: "archeryLevel")
            Readout("Score", value: "\(session.displayedScore)", identifier: "archeryScore")
            Readout(Format.plural(session.displayedArrowsLeft, "Arrow"), value: "\(session.displayedArrowsLeft)",
                    label: "Arrows left", identifier: "arrowsLeft")
        } table: {
            RangeView(session: session, preferences: preferences, reduceMotion: reduceMotion,
                      live: !session.context.options.disableAnimations)
                .padding(.horizontal, Theme.Space.s)
        } tools: {
            LevelsButton(session)
            ToolbarButton("Tip", systemImage: "lightbulb.fill", identifier: "tipButton") {
                session.showingTip.toggle()
            }
            .disabled(!session.isPlaying)
            RestartButton(session)
        } result: {
            ArcheryResult(session: session)
        }
        .levelChrome(session, restartMessage: "Your arrows so far won't count.") {
            ArcheryLevelList(session: session)
        }
    }
}

/// Shown when every arrow is shot, or the time runs out.
struct ArcheryResult: View {
    @ObservedObject var session: ArcherySession

    private var round: ArcheryRound { session.round }

    private var title: String {
        if round.passed {
            return session.hasNextLevel ? "Level \(round.level.number) complete" : "Champion!"
        }
        return round.timedOut ? "Out of time" : "Not quite"
    }

    private var message: String? {
        if round.passed {
            guard round.stars < LevelProgress.maxStars else { return nil }
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

    var body: some View {
        let unshot = max(0, round.level.arrows - round.shots.count)
        ResultPanel(identifier: "archeryResult") {
            ResultStars(round.stars)
            ResultHeadline(title)
            HStack(spacing: 5) {
                ForEach(Array(round.shots.enumerated()), id: \.offset) { _, shot in
                    ScoreChip(hit: shot.hit, size: 32)
                }
                ForEach(0..<unshot, id: \.self) { _ in
                    EmptyChip(size: 32)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Arrows: " + (round.shots.map(\.hit.spokenLabel)
                + Array(repeating: "not shot", count: unshot)).joined(separator: ", "))
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
            LevelResultButtons(session, passed: round.passed, replayTitle: "Shoot Again")
        }
    }
}

/// Every level by venue, with stars and best scores. Passed and current levels can be shot;
/// the rest unlock one by one.
struct ArcheryLevelList: View {
    @ObservedObject var session: ArcherySession

    var body: some View {
        let progress = session.progress
        LevelsSheet(session) {
            ForEach(Chapter.allCases) { chapter in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ChapterHeader(chapter: chapter)
                    ForEach(LevelCatalog.all.filter { $0.chapter == chapter }) { level in
                        let current = level.number == session.levelNumber
                        LevelRow(level: level, unlocked: progress.isUnlocked(level.number),
                                 stars: progress.stars(for: level.number),
                                 best: progress.bestScore(for: level.number), current: current,
                                 spokenState: progress.spokenState(of: level.number, isCurrent: current)) {
                            session.start(level: level.number)
                        }
                        .id(level.number)
                    }
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
    let spokenState: String
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
        .accessibilityValue(spokenState)
        .accessibilityHint(unlocked ? level.summary : "Pass the level before it to unlock.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("level-\(level.number)")
    }
}
