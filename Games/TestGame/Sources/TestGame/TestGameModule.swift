import PlayKit
import SwiftUI

/// A counter "game", and the smallest example of one: a module, a session and a screen built
/// from the shared pieces, with its state saved after every change.
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

@MainActor
final class TestGameSession: ObservableObject, GameSession {
    let context: GameContext
    @Published private(set) var taps: Int

    init(context: GameContext) {
        self.context = context
        taps = context.saveSlot.load(TestGameSave.self)?.taps ?? 0
    }

    var signature: String { "taps:\(taps)" }
    var showsResult: Bool { false }

    func setInView(_ inView: Bool) {}

    func tap() {
        taps += 1
        context.saveSlot.save(TestGameSave(taps: taps))
        context.feedback.play(.tap)
    }
}

struct TestGameScreen: View {
    @StateObject private var session: TestGameSession

    init(context: GameContext) {
        _session = StateObject(wrappedValue: TestGameSession(context: context))
    }

    var body: some View {
        GameScreen(session: session) {
            Readout("Taps", value: "\(session.taps)", identifier: "testGameCount")
        } table: {
            Text("Test Game")
                .font(Typography.display)
                .foregroundStyle(session.context.accent.onTable)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("testGameTitle")
        } tools: {
            ToolbarButton("Tap", systemImage: "hand.tap.fill", identifier: "testGameTap", prominent: true) {
                session.tap()
            }
        } result: {
            EmptyView()
        }
    }
}
