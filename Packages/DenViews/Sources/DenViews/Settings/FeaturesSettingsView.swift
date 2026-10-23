import DenModels
import SwiftUI

public struct FeaturesSettingsView: View {
    @Environment(InputMethodSettingsModel.self) private var preferences

    public init() {}

    public var body: some View {
        SettingsForm {
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
