import SwiftUI

struct SheetNavigationSettingsSection: View {
    @Environment(SheetNavigationManager.self) private var sheetNavigation
    @State private var hintAlphabetDraft = ""
    @State private var ignoredSitesDraft = ""

    var body: some View {
        Section("Vim-style Sheet Navigation") {
            LabeledContent {
                Toggle("", isOn: enabledBinding)
                    .labelsHidden()
            } label: {
                SettingsHelpText {
                    Text("Use j / k and Space hints within Sheets")
                }
            }

            if sheetNavigation.isEnabled {
                LabeledContent("Hint alphabet") {
                    TextField(
                        text: $hintAlphabetDraft,
                        prompt: Text("e.g. asdfghjkl")
                    ) {
                        Text("Hint alphabet")
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .onSubmit {
                        TextInputComposition.performUnlessActive(saveHintAlphabet)
                    }
                }

                if hintAlphabetIsInvalid {
                    SettingsValidationMessage("Use at least two distinct ASCII letters or digits.")
                }

                SettingsActionRow {
                    Button("Save Hint Alphabet", action: saveHintAlphabet)
                        .disabled(
                            hintAlphabetIsInvalid || normalizedHintAlphabet == sheetNavigation.hintAlphabet)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ignored sites")
                    TextEditor(text: $ignoredSitesDraft)
                        .font(.body.monospaced())
                        .frame(height: 80)
                        .accessibilityLabel("Ignored sites")
                    SettingsHelpText {
                        Text("One host per line. A host also ignores its subdomains.")
                    }
                }

                if ignoredSitesAreInvalid {
                    SettingsValidationMessage("Enter hostnames or URLs, one per line.")
                }

                SettingsActionRow {
                    Button("Save Ignored Sites", action: saveIgnoredSites)
                        .disabled(
                            ignoredSitesAreInvalid || normalizedIgnoredSites == sheetNavigation.ignoredHosts)
                }
            }
        }
        .onAppear {
            hintAlphabetDraft = sheetNavigation.hintAlphabet
            ignoredSitesDraft = sheetNavigation.ignoredHosts.joined(separator: "\n")
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding {
            sheetNavigation.isEnabled
        } set: { enabled in
            sheetNavigation.setEnabled(enabled)
        }
    }

    private var normalizedHintAlphabet: String? {
        SheetNavigationManager.normalizeHintAlphabet(hintAlphabetDraft)
    }

    private var hintAlphabetIsInvalid: Bool {
        normalizedHintAlphabet == nil
    }

    private var normalizedIgnoredSites: [String]? {
        SheetNavigationManager.normalizeIgnoredSites(ignoredSitesDraft)
    }

    private var ignoredSitesAreInvalid: Bool {
        normalizedIgnoredSites == nil
    }

    private func saveHintAlphabet() {
        guard sheetNavigation.setHintAlphabet(hintAlphabetDraft) else { return }
        hintAlphabetDraft = sheetNavigation.hintAlphabet
    }

    private func saveIgnoredSites() {
        guard sheetNavigation.setIgnoredSites(ignoredSitesDraft) else { return }
        ignoredSitesDraft = sheetNavigation.ignoredHosts.joined(separator: "\n")
    }
}
