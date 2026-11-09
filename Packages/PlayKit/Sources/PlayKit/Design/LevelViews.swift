import SwiftUI

/// A five-pointed star.
public struct StarShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.04)
        let outer = min(rect.width, rect.height) / 2
        for i in 0..<10 {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let r = i % 2 == 0 ? outer : outer * 0.45
            let p = CGPoint(x: c.x + r * cos(angle), y: c.y + r * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// A level's stars, filled for those earned.
public struct StarRow: View {
    let stars: Int
    let size: CGFloat

    public init(stars: Int, size: CGFloat) {
        self.stars = stars
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size * 0.15) {
            ForEach(0..<LevelProgress.maxStars, id: \.self) { index in
                StarShape()
                    .fill(index < stars ? Theme.highlight : Theme.hairline)
                    .frame(width: size, height: size)
            }
        }
    }
}

/// The stars earned, at the top of a level's result panel.
public struct ResultStars: View {
    let stars: Int

    public init(_ stars: Int) {
        self.stars = stars
    }

    public var body: some View {
        StarRow(stars: stars, size: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(stars) of \(LevelProgress.maxStars) stars")
            .accessibilityIdentifier("resultStars")
    }
}

/// Toolbar button that opens the level list.
public struct LevelsButton<Session: LevelSession>: View {
    let session: Session

    public init(_ session: Session) {
        self.session = session
    }

    public var body: some View {
        ToolbarButton("Levels", systemImage: "square.grid.3x3.fill", identifier: "levels") {
            session.showingLevels = true
        }
    }
}

/// Toolbar button that restarts the level, asking first if there are shots to lose.
public struct RestartButton<Session: LevelSession>: View {
    @ObservedObject var session: Session

    public init(_ session: Session) {
        self.session = session
    }

    public var body: some View {
        ToolbarButton("Restart", systemImage: "arrow.counterclockwise", identifier: "restart") {
            session.requestRestart()
        }
        .disabled(!session.canRestart)
    }
}

/// The buttons under a level's result: on to the next level after a pass, another go
/// otherwise, and always the way to the level list.
public struct LevelResultButtons<Session: LevelSession>: View {
    @ObservedObject var session: Session
    let passed: Bool
    let replayTitle: String

    /// - Parameter replayTitle: what playing a passed level again is called, such as "Replay Level".
    public init(_ session: Session, passed: Bool, replayTitle: String) {
        self.session = session
        self.passed = passed
        self.replayTitle = replayTitle
    }

    public var body: some View {
        VStack(spacing: Theme.Space.s) {
            if passed && session.hasNextLevel {
                Button("Next Level") { session.nextLevel() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("resultNext")
                Button(replayTitle) { session.retry() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("resultReplay")
            } else {
                Button(passed ? replayTitle : "Try Again") { session.retry() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("resultRetry")
            }
            Button("All Levels") { session.showingLevels = true }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("resultLevels")
        }
    }
}

/// The level list's sheet: a summary of the stars, then the game's own rows. It opens scrolled
/// to the current level, so each row must carry its level number as its `id`.
public struct LevelsSheet<Session: LevelSession, Rows: View>: View {
    @ObservedObject var session: Session
    let rows: Rows

    public init(_ session: Session, @ViewBuilder rows: () -> Rows) {
        self.session = session
        self.rows = rows()
    }

    public var body: some View {
        SheetPage("Levels") {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        Text("\(session.progress.totalStars) of \(session.levelCount * LevelProgress.maxStars) stars · \(session.levelCount.formatted()) levels")
                            .font(Typography.label)
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityIdentifier("levelSummary")
                        rows
                    }
                    .padding(Theme.Space.l)
                }
                .onAppear { proxy.scrollTo(session.levelNumber, anchor: .center) }
            }
        }
        .environment(\.accent, session.context.accent)
    }
}

private struct LevelChrome<Session: LevelSession, Levels: View>: ViewModifier {
    @ObservedObject var session: Session
    let restartMessage: String
    let levels: () -> Levels

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { session.showingLevels }, set: { session.showingLevels = $0 })) {
                levels()
            }
            .confirmation("Restart this level?",
                          isPresented: Binding(get: { session.confirmingRestart }, set: { session.confirmingRestart = $0 }),
                          message: restartMessage, confirm: "Restart") {
                session.retry()
            }
    }
}

extension View {
    /// Attaches what a levelled game shows over its screen: the level list and the question
    /// asked before a restart throws shots away.
    public func levelChrome<Session: LevelSession, Levels: View>(
        _ session: Session, restartMessage: String, @ViewBuilder levels: @escaping () -> Levels
    ) -> some View {
        modifier(LevelChrome(session: session, restartMessage: restartMessage, levels: levels))
    }
}
