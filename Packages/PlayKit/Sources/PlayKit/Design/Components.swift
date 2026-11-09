import SwiftUI

/// Flat button on a game table. Uses the game's accent from the environment.
struct TableButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
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
                    .frame(height: 24)
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
struct IconButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
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
