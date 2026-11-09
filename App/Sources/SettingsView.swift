import PlayKit
import SwiftUI

/// Shared settings plus each game's own rows, supplied by its module.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SheetPage("Settings") {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    SettingsPanel("General") {
                        SettingsToggleRow("Sound effects", detail: "Off by default. Follows the silent switch.",
                                          isOn: $settings.soundEnabled, identifier: "soundToggle")
                        SettingsDivider()
                        SettingsToggleRow("Haptics", detail: "Light taps when cards land.",
                                          isOn: $settings.hapticsEnabled, identifier: "hapticsToggle")
                        SettingsDivider()
                        SettingsChoiceRow("Appearance",
                                          choices: Appearance.allCases.map { (value: $0, label: $0.title) },
                                          selection: $settings.appearance, identifier: "appearance")
                    }
                    ForEach(model.games) { game in
                        if let rows = game.module.makeSettingsSection(context: model.context(for: game)) {
                            SettingsPanel(game.module.title) {
                                rows
                            }
                        }
                    }
                    SettingsPanel("About") {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text("Between Stops \(Self.version)")
                                .font(Typography.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Works fully offline. No accounts, ads, analytics or tracking. Your games and statistics never leave this phone.")
                                .font(Typography.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.vertical, Theme.Space.m)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Theme.Space.l)
            }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
