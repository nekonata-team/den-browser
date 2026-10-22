import DenPresentationModels
import SwiftUI

public struct TerminalSettingsView: View {
    @Environment(TerminalSettingsModel.self) private var preferences
    @State private var zellijPathDraft = ""
    @State private var zmxPathDraft = ""
    @State private var hasLoadedDraft = false

    public init() {}

    public var body: some View {
        SettingsForm {
            Section("Permissions") {
                SettingsHelpText {
                    Text("Terminal Boards may need Full Disk Access to access protected files.")
                }

                SettingsActionRow {
                    Button("Open Full Disk Access Settings") {
                        preferences.openFullDiskAccessSettings()
                    }
                }
            }

            Section("Zellij") {
                TextField(
                    text: $zellijPathDraft,
                    prompt: Text("/usr/local/bin/zellij")
                ) {
                    Text("Executable")
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive(saveZellijPath)
                }

                SettingsHelpText {
                    Text("Use the absolute path to the Zellij executable.")
                }

                SettingsActionRow {
                    Button("Save Executable Path") {
                        saveZellijPath()
                    }
                    .disabled(!hasZellijPathChanges)
                }
            }

            Section("zmx") {
                TextField(
                    text: $zmxPathDraft,
                    prompt: Text("/usr/local/bin/zmx")
                ) {
                    Text("Executable")
                }
                .onSubmit {
                    TextInputComposition.performUnlessActive(saveZmxPath)
                }

                SettingsHelpText {
                    Text("Use the absolute path to the zmx executable.")
                }

                SettingsActionRow {
                    Button("Save Executable Path") {
                        saveZmxPath()
                    }
                    .disabled(!hasZmxPathChanges)
                }
            }
        }
        .onAppear {
            guard !hasLoadedDraft else { return }
            zellijPathDraft = preferences.zellijPath
            zmxPathDraft = preferences.zmxPath
            hasLoadedDraft = true
        }
    }

    private var hasZellijPathChanges: Bool {
        zellijPathDraft.trimmingCharacters(in: .whitespacesAndNewlines) != preferences.zellijPath
    }

    private func saveZellijPath() {
        preferences.setZellijPath(zellijPathDraft)
        zellijPathDraft = preferences.zellijPath
    }

    private var hasZmxPathChanges: Bool {
        zmxPathDraft.trimmingCharacters(in: .whitespacesAndNewlines) != preferences.zmxPath
    }

    private func saveZmxPath() {
        preferences.setZmxPath(zmxPathDraft)
        zmxPathDraft = preferences.zmxPath
    }
}
