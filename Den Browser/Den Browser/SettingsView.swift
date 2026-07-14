import SwiftUI

struct SettingsView: View {
    @Environment(SheetNavigationManager.self) private var sheetNavigation
    @State private var hintAlphabetDraft = ""
    @State private var ignoredSitesDraft = ""

    var body: some View {
        TabView {
            ProfilesSettingsView()
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }

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

private struct ProfilesSettingsView: View {
    @Environment(ProfileManager.self) private var profileManager
    @State private var newName = ""
    @State private var newColor: ProfileColor = .purple
    @State private var profileToDelete: ProfileState?

    var body: some View {
        Form {
            Section("Profiles") {
                ForEach(profileManager.profiles) { profile in
                    ProfileSettingsRow(
                        profile: profile,
                        canDelete: profile.webProfileStore != .default,
                        onDelete: { profileToDelete = profile })
                }
            }

            Section("New Profile") {
                TextField("Name", text: $newName)
                Picker("Color", selection: $newColor) {
                    ForEach(ProfileColor.allCases) { color in
                        Label(color.label, systemImage: "circle.fill")
                            .foregroundStyle(color.color)
                            .tag(color)
                    }
                }
                Button("Create Profile") {
                    guard profileManager.createProfile(name: newName, color: newColor) != nil else { return }
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Delete \(profileToDelete?.name ?? "Profile")?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } })
        ) {
            Button("Delete Profile", role: .destructive) {
                guard let profileToDelete else { return }
                Task {
                    _ = await profileManager.deleteProfile(profileToDelete.id)
                    self.profileToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("Its Den, open window, and website data will be removed.")
        }
        .alert(
            "Profile Error",
            isPresented: Binding(
                get: { profileManager.errorMessage != nil },
                set: { if !$0 { profileManager.clearError() } })
        ) {
            Button("OK") { profileManager.clearError() }
        } message: {
            Text(profileManager.errorMessage ?? "")
        }
    }
}

private struct ProfileSettingsRow: View {
    let profile: ProfileState
    let canDelete: Bool
    let onDelete: () -> Void

    @Environment(ProfileManager.self) private var profileManager
    @State private var name: String

    init(profile: ProfileState, canDelete: Bool, onDelete: @escaping () -> Void) {
        self.profile = profile
        self.canDelete = canDelete
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        HStack {
            Circle().fill(profile.color.color).frame(width: 11, height: 11)
            TextField("Profile name", text: $name)
                .onSubmit(saveName)
            Picker("Color", selection: colorBinding) {
                ForEach(ProfileColor.allCases) { color in
                    Text(color.label).tag(color)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            if canDelete {
                Button("Delete", role: .destructive, action: onDelete)
            } else {
                Text("Required").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: saveName)
    }

    private var colorBinding: Binding<ProfileColor> {
        Binding {
            profileManager.profile(id: profile.id)?.color ?? profile.color
        } set: { color in
            _ = profileManager.updateProfile(profile.id, color: color)
        }
    }

    private func saveName() {
        guard profileManager.updateProfile(profile.id, name: name) else {
            name = profileManager.profile(id: profile.id)?.name ?? profile.name
            return
        }
        name = profileManager.profile(id: profile.id)?.name ?? name
    }
}
