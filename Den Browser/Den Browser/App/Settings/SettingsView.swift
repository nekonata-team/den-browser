import AppKit
import DenModels
import DenViews
import SwiftUI

struct SettingsView: View {
    @Environment(ProfileManager.self) private var profileManager

    var body: some View {
        DenViews.SettingsView(
            onClose: { NSColorPanel.shared.close() },
            content: { section in
                switch section {
                case .profiles: ProfilesSettingsView()
                case .appearance:
                    AppearanceSettingsView(
                        sheetScaleRange: AppPreferences.sheetScaleRange,
                        defaultSheetScale: AppPreferences.defaultSheetScale
                    )
                case .shortcuts: ShortcutsSettingsView()
                case .essentials: EssentialsSettingsView()
                case .terminal: TerminalSettingsView()
                case .web: WebSettingsView()
                case .features: FeaturesSettingsView()
                case .skills:
                    SkillsSettingsView(
                        installCommand: SkillMaintenanceAction.install.command,
                        updateCommand: SkillMaintenanceAction.update.command,
                        install: { profileManager.runSkillMaintenance(.install) },
                        update: { profileManager.runSkillMaintenance(.update) })
                }
            })
    }
}

private struct WebSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(ProfileManager.self) private var profileManager
    var body: some View {
        DenViews.WebSettingsView(
            model: WebSettingsModel(preferences: preferences, manager: profileManager),
            defaultBrowser: DefaultBrowserSettingsModel(preferences: preferences),
            openPopup: { profileManager.presentUBOLitePopup(anchorView: $0) })
    }
}
