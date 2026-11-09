import SwiftUI

/// The frame every game is played in: a top bar (back to the game list, the game's readouts,
/// Settings), the table, a thumb-height toolbar, and the result panel over it all.
///
/// It also tells the session when the game is in view: on screen, in the foreground, and not
/// covered by Settings or by something of the session's own (`coversTable`).
public struct GameScreen<Session: GameSession, Readouts: View, Table: View, Tools: View, Result: View>: View {
    @ObservedObject private var session: Session
    @ObservedObject private var context: GameContext
    private let readouts: Readouts
    private let table: Table
    private let tools: Tools
    private let result: Result
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(session: Session,
                @ViewBuilder readouts: () -> Readouts,
                @ViewBuilder table: () -> Table,
                @ViewBuilder tools: () -> Tools,
                @ViewBuilder result: () -> Result) {
        self.session = session
        self.context = session.context
        self.readouts = readouts()
        self.table = table()
        self.tools = tools()
        self.result = result()
    }

    public var body: some View {
        let animate = context.animates(reduceMotion: reduceMotion)
        let inView = appeared && scenePhase == .active && !context.isCovered && !session.coversTable
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) {
                IconButton(systemImage: "chevron.left", label: "Games", identifier: "back") { session.leave() }
                Spacer(minLength: 0)
                HStack(spacing: Theme.Space.xl) {
                    readouts
                }
                .foregroundStyle(context.accent.onTable)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                Spacer(minLength: 0)
                IconButton(systemImage: "gearshape.fill", label: "Settings", identifier: "settings") {
                    context.openSettings()
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.xs)
            if context.options.showBoardSignature {
                Text(session.signature)
                    .font(.system(size: 6))
                    .lineLimit(1)
                    .foregroundStyle(context.accent.onTable)
                    .accessibilityIdentifier("boardSignature")
            }
            table
            HStack(spacing: Theme.Space.s) {
                tools
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.xs)
            .padding(.bottom, Theme.Space.s)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .background(context.accent.table.ignoresSafeArea())
        .overlay {
            if session.showsResult {
                result
                    .transition(animate ? .opacity.combined(with: .scale(scale: 0.96)) : .opacity)
            }
        }
        .animation(animate ? .easeOut(duration: 0.25) : nil, value: session.showsResult)
        .environment(\.accent, context.accent)
        .onAppear { appeared = true }
        .onChange(of: inView, initial: true) { _, inView in session.setInView(inView) }
        // A view on its way out may never see another change, so say so directly.
        .onDisappear { session.setInView(false) }
    }
}

/// The explanation under a result panel's headline.
public struct ResultMessage: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(Theme.inkSecondary)
            .multilineTextAlignment(.center)
    }
}

/// A number over its name, for the top bar: "12" over "Moves".
public struct Readout: View {
    let title: String
    let value: String
    let label: String
    let spokenValue: String
    let identifier: String

    /// - Parameters:
    ///   - label: what VoiceOver calls it, when the title is too short to stand alone.
    ///   - spokenValue: what VoiceOver reads for the value, when the digits are not enough.
    public init(_ title: String, value: String, label: String? = nil, spokenValue: String? = nil, identifier: String) {
        self.title = title
        self.value = value
        self.label = label ?? title
        self.spokenValue = spokenValue ?? value
        self.identifier = identifier
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Typography.numeric)
                .lineLimit(1)
            Text(title)
                .font(Typography.caption)
                .opacity(0.8)
        }
        .frame(minWidth: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue)
        .accessibilityIdentifier(identifier)
    }
}

/// The panel shown over the table when a game or level ends. VoiceOver stays inside it until
/// it is dismissed.
public struct ResultPanel<Content: View>: View {
    let identifier: String
    let content: Content

    public init(identifier: String, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.content = content()
    }

    public var body: some View {
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
        .accessibilityAddTraits(.isModal)
    }

    private var panel: some View {
        VStack(spacing: Theme.Space.l) {
            content
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 420)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous).fill(Theme.surface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

public struct ResultHeadline: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Typography.display)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A sheet with a title and a Done button, on the app's background.
public struct SheetPage<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.dismiss) private var dismiss

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            content
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(title)
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

extension View {
    /// Asks before throwing a game in progress away.
    public func confirmation(_ title: String, isPresented: Binding<Bool>, message: String, confirm: String,
                             action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(confirm, role: .destructive, action: action)
            // Not a cancel-role button: iOS 26 hides those in dialogs, and an explicit way out is
            // easier on a moving train than tapping outside.
            Button("Keep Playing") {}
        } message: {
            Text(message)
        }
    }
}
