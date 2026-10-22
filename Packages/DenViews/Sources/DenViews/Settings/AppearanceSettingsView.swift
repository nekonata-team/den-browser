import DenPresentationModels
import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(AppearanceModel.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    public init(sheetScaleRange: ClosedRange<Int>, defaultSheetScale: Int) {
        self.sheetScaleRange = sheetScaleRange
        self.defaultSheetScale = defaultSheetScale
    }

    private let sheetScaleRange: ClosedRange<Int>
    private let defaultSheetScale: Int

    public var body: some View {
        SettingsForm {
            Section("Desk Switcher") {
                Picker("Alignment", selection: deskSwitcherAlignmentBinding) {
                    ForEach(DeskSwitcherAlignment.allCases) { alignment in
                        Text(alignment.label).tag(alignment)
                    }
                }
                .pickerStyle(.radioGroup)

                SettingsHelpText {
                    Text(
                        "Align the Desk list and New Desk button within the work area when they fit. "
                            + "Applies immediately across Profiles.")
                }
            }

            Section("Board Centering") {
                Picker("Centering", selection: boardCenteringBinding) {
                    ForEach(FocusedBoardCentering.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                SettingsHelpText {
                    Text(boardCenteringDescription)
                }
            }

            Section("Sheet Scale") {
                HStack(spacing: 12) {
                    Text("50%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: sheetScaleBinding,
                        in: Double(
                            sheetScaleRange.lowerBound)...Double(
                                sheetScaleRange.upperBound),
                        step: 1)
                    Text("200%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Scale") {
                    Text("\(preferences.sheetScale)%")
                        .monospacedDigit()
                }

                SettingsHelpText {
                    Text("Applies to every Sheet across Profiles immediately.")
                }

                SettingsActionRow {
                    Button("Reset Sheet Scale") {
                        preferences.setSheetScale(defaultSheetScale)
                    }
                    .disabled(preferences.sheetScale == defaultSheetScale)
                }
            }

            Section("Motion") {
                Picker("Motion", selection: motionBinding) {
                    ForEach(MotionPreference.allCases) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .pickerStyle(.radioGroup)

                SettingsHelpText {
                    Text(motionDescription)
                }
            }

            Section("Drawer") {
                Picker("Drawer Style", selection: drawerStyleBinding) {
                    ForEach(DrawerStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)

                SettingsHelpText {
                    Text(drawerStyleDescription)
                }
            }
        }
    }

    private var deskSwitcherAlignmentBinding: Binding<DeskSwitcherAlignment> {
        Binding {
            preferences.deskSwitcherAlignment
        } set: { alignment in
            preferences.setDeskSwitcherAlignment(alignment)
        }
    }

    private var boardCenteringBinding: Binding<FocusedBoardCentering> {
        Binding {
            preferences.boardCentering
        } set: { mode in
            preferences.setBoardCentering(mode)
        }
    }

    private var boardCenteringDescription: String {
        switch preferences.boardCentering {
        case .always:
            "Keep the focused board centered in the window, even at the ends."
        case .never:
            "Do not center focused Boards. Off-screen Boards scroll only to the nearest edge."
        case .onOverflow:
            "Center a focused Board when it does not fit beside the previously focused Board."
        }
    }

    private var motionBinding: Binding<MotionPreference> {
        Binding {
            preferences.motionPreference
        } set: { preference in
            preferences.setMotionPreference(preference)
        }
    }

    private var drawerStyleBinding: Binding<DrawerStyle> {
        Binding {
            preferences.drawerStyle
        } set: { style in
            preferences.setDrawerStyle(style)
        }
    }

    private var drawerStyleDescription: String {
        switch preferences.drawerStyle {
        case .floating:
            "Show the Drawer as a centered floating card. Press f while open to expand to full width."
        case .bottom:
            "Show the Drawer as a full-width bottom sheet. Press f while open to contract to floating."
        }
    }

    private var sheetScaleBinding: Binding<Double> {
        Binding {
            Double(preferences.sheetScale)
        } set: { scale in
            preferences.setSheetScale(Int(scale.rounded()))
        }
    }

    private var motionDescription: String {
        switch preferences.motionPreference {
        case .followSystem:
            "Use the macOS setting. Reduce Motion is currently \(systemReduceMotion ? "on" : "off")."
        case .standard:
            "Use Den’s standard smooth motion, even when Reduce Motion is enabled in macOS."
        case .reduced:
            "Remove spatial motion and use brief opacity changes."
        }
    }
}
