import SwiftUI

struct SettingsView: View {
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        TabView {
            ProfilesSettingsView()
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

            ShortcutsSettingsView()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }

            EssentialsSettingsView()
                .tabItem {
                    Label("Essentials", systemImage: "sparkles")
                }

            TerminalSettingsView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }

            SettingsForm {
                DefaultBrowserSettingsSection()

                SheetNavigationSettingsSection()

                Section("Experimental Picture in Picture") {
                    LabeledContent {
                        Toggle("", isOn: pipBinding)
                            .labelsHidden()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            SettingsHelpText {
                                Text("Allows playing video in a Picture-in-Picture window.")
                            }
                            Text(
                                "Note: Uses private APIs. Future macOS updates may break it. Changes apply to new sheets or after restart."
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

            }
            .tabItem {
                Label("Features", systemImage: "puzzlepiece.extension")
            }
        }
        .frame(width: 520, height: 500)
    }

    private var pipBinding: Binding<Bool> {
        Binding {
            preferences.nativePictureInPictureEnabled
        } set: { enabled in
            preferences.setNativePictureInPictureEnabled(enabled)
        }
    }

}

private struct TerminalSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var zellijPathDraft = ""
    @State private var zmxPathDraft = ""
    @State private var hasLoadedDraft = false

    var body: some View {
        SettingsForm {
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

private struct AppearanceSettingsView: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        SettingsForm {
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
                            AppPreferences.sheetScaleRange.lowerBound)...Double(
                                AppPreferences.sheetScaleRange.upperBound),
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
                        preferences.setSheetScale(AppPreferences.defaultSheetScale)
                    }
                    .disabled(preferences.sheetScale == AppPreferences.defaultSheetScale)
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

private struct ProfilesSettingsView: View {
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var newName = ""
    @State private var newColor: ProfileColor = .purple
    @State private var profileToDelete: ProfileState?

    var body: some View {
        SettingsForm {
            Section("Profiles") {
                ForEach(profileManager.profiles) { profile in
                    ProfileSettingsRow(
                        profile: profile,
                        canDelete: profile.webProfileStore != .default,
                        onDelete: { profileToDelete = profile })
                }
            }

            Section("New Profile") {
                HStack {
                    ProfileColorDot(color: newColor)
                    TextField(
                        text: $newName,
                        prompt: Text("e.g. Work")
                    ) {
                        Text("Profile name")
                    }
                    .labelsHidden()
                    .onSubmit {
                        TextInputComposition.performUnlessActive(createProfile)
                    }
                    Picker("Color", selection: $newColor) {
                        ForEach(ProfileColor.allCases) { color in
                            Text(color.label).tag(color)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                SettingsActionRow {
                    Button("Create Profile") {
                        createProfile()
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .confirmationDialog(
            "Delete \(profileToDelete?.name ?? "Profile")?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } })
        ) {
            Button("Delete Profile", role: .destructive) {
                guard let profileToDelete else { return }
                Task {
                    if await profileManager.deleteProfile(profileToDelete.id) {
                        dismissWindow(value: profileToDelete.id)
                    }
                    self.profileToDelete = nil
                }
            }
            .keyboardShortcut(.defaultAction)
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
        .sheet(
            isPresented: Binding(
                get: {
                    profileManager.clearBrowsingDataProfileID != nil
                        && profileManager.clearBrowsingDataWindowID == nil
                },
                set: {
                    if !$0 {
                        profileManager.clearBrowsingDataProfileID = nil
                        profileManager.clearBrowsingDataWindowID = nil
                    }
                }
            )
        ) {
            if let id = profileManager.clearBrowsingDataProfileID {
                ClearBrowsingDataView(profileID: id) {
                    profileManager.clearBrowsingDataProfileID = nil
                    profileManager.clearBrowsingDataWindowID = nil
                }
            }
        }
    }

    private func createProfile() {
        guard profileManager.createProfile(name: newName, color: newColor) != nil else { return }
        newName = ""
    }
}

private struct ProfileColorDot: View {
    let color: ProfileColor

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: 10, height: 10)
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
            ProfileColorDot(color: profile.color)
            TextField(
                text: $name,
                prompt: Text("e.g. Work")
            ) {
                Text("Profile name")
            }
            .labelsHidden()
            .onSubmit { TextInputComposition.performUnlessActive(saveName) }
            Picker("Color", selection: colorBinding) {
                ForEach(ProfileColor.allCases) { color in
                    Text(color.label).tag(color)
                }
            }
            .labelsHidden()
            .frame(width: 100)
            Button {
                profileManager.clearBrowsingDataProfileID = profile.id
                profileManager.clearBrowsingDataWindowID = nil
            } label: {
                Image(systemName: "eraser")
            }
            .buttonStyle(.borderless)
            .help("Clear Browsing Data…")
            .accessibilityLabel("Clear Browsing Data for \(profile.name)")

            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete Profile")
                .accessibilityLabel("Delete Profile \(profile.name)")
            } else {
                Button {
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(true)
                .help("Default Profile (Personal) cannot be deleted")
                .accessibilityLabel("Default Profile (Personal) cannot be deleted")
            }
        }
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
