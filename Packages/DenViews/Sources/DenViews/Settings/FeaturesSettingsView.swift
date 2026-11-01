import DenModels
import SwiftUI

public struct FeaturesSettingsView: View {
    @Environment(InputMethodSettingsModel.self) private var preferences
    @Binding private var drawerAutoCleanup: Bool

    public init(drawerAutoCleanup: Binding<Bool>) {
        self._drawerAutoCleanup = drawerAutoCleanup
    }

    public var body: some View {
        SettingsForm {
            Section("Drawer") {
                Toggle("Automatically discard inactive Drawer Items", isOn: $drawerAutoCleanup)
                SettingsHelpText {
                    Text(
                        "When opening Drawer, discard Web and Terminal Items inactive for 12 hours. These Items cannot be restored; unsaved work and running processes may be lost."
                    )
                }
            }

            Section("Input Method") {
                Toggle(
                    "Remember input method per Board",
                    isOn: Binding(
                        get: { preferences.rememberBoardInputMethod },
                        set: { preferences.setRememberBoardInputMethod($0) }
                    )
                )

                SettingsHelpText {
                    Text("Automatically restores the last used keyboard input method when focusing a Board.")
                }
            }
        }
    }
}
