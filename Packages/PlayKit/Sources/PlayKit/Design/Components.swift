import SwiftUI

/// Flat button on a game table. Uses the game's accent from the environment.
public struct TableButtonStyle: ButtonStyle {
    public var prominent: Bool

    public init(prominent: Bool = false) {
        self.prominent = prominent
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledTableButton(configuration: configuration, prominent: prominent)
    }

    private struct StyledTableButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.accent) private var accent
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(prominent ? Theme.onHighlight : accent.onTable)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(prominent ? Theme.highlight : accent.tableControl)
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
        }
    }
}

/// A large toolbar button: icon above a short label, at least `Theme.minTouchTarget` tall.
public struct ToolbarButton: View {
    let title: String
    let systemImage: String
    let identifier: String
    let prominent: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String, identifier: String, prominent: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.identifier = identifier
        self.prominent = prominent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typography.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(TableButtonStyle(prominent: prominent))
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// A round icon-only button for the top bar.
public struct IconButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    let action: () -> Void

    public init(systemImage: String, label: String, identifier: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.identifier = identifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .frame(width: Theme.minTouchTarget, height: Theme.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(TableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// Standard game top bar: back to the game list, a centre slot, and settings.
public struct GameTopBar<Center: View>: View {
    let onBack: () -> Void
    let onSettings: () -> Void
    let center: Center

    public init(onBack: @escaping () -> Void, onSettings: @escaping () -> Void, @ViewBuilder center: () -> Center) {
        self.onBack = onBack
        self.onSettings = onSettings
        self.center = center()
    }

    public var body: some View {
        HStack(spacing: Theme.Space.m) {
            IconButton(systemImage: "chevron.left", label: "Games", identifier: "back", action: onBack)
            Spacer(minLength: 0)
            center
            Spacer(minLength: 0)
            IconButton(systemImage: "gearshape.fill", label: "Settings", identifier: "settings", action: onSettings)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.xs)
    }
}

/// Full-width filled button in the game's accent colour.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accent) private var accent

        var body: some View {
            configuration.label
                .font(Typography.headline)
                .foregroundStyle(accent.onFill)
                .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget + 4)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(accent.fill))
                .opacity(configuration.isPressed ? 0.75 : 1)
                .contentShape(Rectangle())
        }
    }
}

/// Full-width quiet button for secondary actions.
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.headline)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.minTouchTarget + 4)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous).fill(Theme.hairline))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// A short message in a capsule, shown above the toolbar.
public struct Toast: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Typography.label)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.m)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .accessibilityIdentifier("toast")
    }
}

/// A labelled number, used on the win screen and the statistics screen.
public struct StatValue: View {
    let title: String
    let value: String

    public init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Typography.title)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}
