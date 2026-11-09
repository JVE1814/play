import SwiftUI

public struct SettingsPanel<Content: View>: View {
    let title: String
    let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title.uppercased())
                .font(Typography.caption)
                .foregroundStyle(Theme.inkSecondary)
                .padding(.horizontal, Theme.Space.l)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.xs)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous).fill(Theme.surface))
        }
    }
}

public struct SettingsToggleRow: View {
    let title: String
    let detail: String?
    let identifier: String
    @Binding var isOn: Bool

    public init(_ title: String, detail: String? = nil, isOn: Binding<Bool>, identifier: String) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
        self.identifier = identifier
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .tint(Accent.jade.fill)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(minHeight: Theme.minTouchTarget)
        .accessibilityIdentifier(identifier)
    }
}

public struct SettingsChoiceRow<Value: Hashable>: View {
    let title: String
    let detail: String?
    let choices: [(value: Value, label: String)]
    let identifier: String
    @Binding var selection: Value

    public init(_ title: String, detail: String? = nil, choices: [(value: Value, label: String)],
                selection: Binding<Value>, identifier: String) {
        self.title = title
        self.detail = detail
        self.choices = choices
        self._selection = selection
        self.identifier = identifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title)
                .font(Typography.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Picker(title, selection: $selection) {
                ForEach(choices.indices, id: \.self) { index in
                    Text(choices[index].label).tag(choices[index].value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier(identifier)
            if let detail {
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }
}

public struct SettingsDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, Theme.Space.l)
    }
}
