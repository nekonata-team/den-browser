import SwiftUI

struct SettingsView: View {
    @Environment(SheetNavigationManager.self) private var sheetNavigation
    @State private var hintAlphabetDraft = ""
    @State private var ignoredSitesDraft = ""

    var body: some View {
        TabView {
            Form {
                LabeledContent {
                    Toggle("", isOn: enabledBinding)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Vim-style Sheet Navigation")
                        Text("Use j / k and Space hints within Sheets")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if sheetNavigation.isEnabled {
                    LabeledContent("Hint alphabet") {
                        TextField("asdfghjkl", text: $hintAlphabetDraft)
                            .labelsHidden()
                            .frame(width: 180)
                            .onSubmit(saveHintAlphabet)
                    }

                    if hintAlphabetIsInvalid {
                        Text("Use at least two distinct ASCII letters or digits.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Save Hint Alphabet", action: saveHintAlphabet)
                        .disabled(hintAlphabetIsInvalid || normalizedHintAlphabet == sheetNavigation.hintAlphabet)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ignored sites")
                        TextEditor(text: $ignoredSitesDraft)
                            .font(.body.monospaced())
                            .frame(height: 80)
                            .accessibilityLabel("Ignored sites")
                        Text("One host per line. A host also ignores its subdomains.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if ignoredSitesAreInvalid {
                        Text("Enter hostnames or URLs, one per line.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button("Save Ignored Sites", action: saveIgnoredSites)
                        .disabled(
                            ignoredSitesAreInvalid || normalizedIgnoredSites == sheetNavigation.ignoredHosts)
                }

                Text("Navigation runs locally in each Sheet and sends no browsing data elsewhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding()
            .tabItem {
                Label("Features", systemImage: "puzzlepiece.extension")
            }
        }
        .frame(width: 520, height: 500)
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
