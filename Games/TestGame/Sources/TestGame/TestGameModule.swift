import PlayKit
import SwiftUI

/// A counter "game". It uses the shared protocol, design tokens and save slot like a real game.
public struct TestGameModule: GameModule {
    public init() {}

    public var id: String { "testgame" }
    public var title: String { "Test Game" }
    public var tagline: String { "A placeholder that only exists in test builds" }
    public var accent: Accent { .grape }

    @MainActor public func makeIcon() -> AnyView {
        AnyView(
            Circle()
                .fill(Accent.grape.onFill)
                .overlay(Image(systemName: "hand.tap.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Accent.grape.fill))
                .padding(6)
        )
    }

    @MainActor public func makeGameView(context: GameContext) -> AnyView {
        AnyView(TestGameScreen(context: context))
    }

    @MainActor public func statusLine(context: GameContext) -> String? {
        guard let save = context.saveSlot.load(TestGameSave.self), save.taps > 0 else { return nil }
        return "\(save.taps) taps so far"
    }
}

struct TestGameSave: Codable {
    var taps: Int
}

struct TestGameScreen: View {
    let context: GameContext
    @State private var taps: Int

    init(context: GameContext) {
        self.context = context
        _taps = State(initialValue: context.saveSlot.load(TestGameSave.self)?.taps ?? 0)
    }

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            GameTopBar(onBack: { context.exit() }, onSettings: { context.openSettings() }) {
                Text("Test Game")
                    .font(Typography.headline)
                    .foregroundStyle(context.accent.onTable)
                    .accessibilityIdentifier("testGameTitle")
            }
            Spacer()
            Text("\(taps)")
                .font(Typography.display)
                .monospacedDigit()
                .foregroundStyle(context.accent.onTable)
                .accessibilityLabel("Taps")
                .accessibilityValue("\(taps)")
                .accessibilityIdentifier("testGameCount")
            Button {
                taps += 1
                context.saveSlot.save(TestGameSave(taps: taps))
                context.feedback.play(.tap)
            } label: {
                Text("Tap")
                    .font(Typography.headline)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget + 8)
            }
            .buttonStyle(TableButtonStyle(prominent: true))
            .padding(.horizontal, Theme.Space.xxl)
            .accessibilityIdentifier("testGameTap")
            Spacer()
        }
        .background(context.accent.table.ignoresSafeArea())
        .environment(\.accent, context.accent)
    }
}
