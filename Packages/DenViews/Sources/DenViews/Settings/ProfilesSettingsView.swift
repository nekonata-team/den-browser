import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

public struct ProfilesSettingsView: View {
    @Environment(ProfileSettingsModel.self) private var profileManager
    @State private var newName = ""
    @State private var newColor: ProfileColor = .purple
    @State private var profileToDelete: ProfileState?

    public init() {}

    public var body: some View {
        SettingsForm {
            Section("Profiles") {
                ForEach(profileManager.profiles) { profile in
                    ProfileSettingsRow(
                        profile: profile,
                        canDelete: profileManager.canDeleteProfile(profile.id),
                        onDelete: { profileToDelete = profile })
                }
            }

            Section("New Profile") {
                HStack {
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
                    HStack(spacing: 8) {
                        ColorPicker("Color", selection: newColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .accessibilityLabel("New profile color")
                        ProfileColorPalette(selection: $newColor)
                    }
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
                    _ = await profileManager.deleteProfile(profileToDelete.id)
                    self.profileToDelete = nil
                }
            }
            .disabled(profileToDelete.map { !profileManager.canDeleteProfile($0.id) } ?? true)
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { profileToDelete = nil }
        } message: {
            Text("Its Den, website data, and extension data will be removed.")
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
                },
                set: {
                    if !$0 {
                        profileManager.dismissClearBrowsingData()
                    }
                }
            )
        ) {
            if let id = profileManager.clearBrowsingDataProfileID {
                ClearBrowsingDataView(
                    profile: profileManager.profile(id: id),
                    onClear: { categories in
                        _ = await profileManager.clearBrowsingData(categories: categories, profileID: id)
                    },
                    onDismiss: {
                        profileManager.dismissClearBrowsingData()
                    }
                )
            }
        }
    }

    private func createProfile() {
        guard profileManager.createProfile(name: newName, color: newColor) != nil else { return }
        newName = ""
    }

    private var newColorBinding: Binding<Color> {
        Binding {
            profileDisplayColor(for: newColor)
        } set: { color in
            if let profileColor = profileColor(from: color) {
                newColor = profileColor
            }
        }
    }
}

private struct ProfileColorPalette: View {
    @Binding var selection: ProfileColor

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ProfileColor.presets) { preset in
                Button {
                    selection = preset
                } label: {
                    Circle()
                        .fill(profileDisplayColor(for: preset))
                        .frame(width: 16, height: 16)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.primary.opacity(selection == preset ? 0.9 : 0.25),
                                    lineWidth: selection == preset ? 2 : 1)
                        }
                        .padding(2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(profileColorLabel(for: preset))
                .accessibilityAddTraits(selection == preset ? [.isSelected] : [])
            }
        }
        .fixedSize()
    }
}

private struct ProfileSettingsRow: View {
    let profile: ProfileState
    let canDelete: Bool
    let onDelete: () -> Void

    @Environment(ProfileSettingsModel.self) private var profileManager
    @State private var name: String

    init(profile: ProfileState, canDelete: Bool, onDelete: @escaping () -> Void) {
        self.profile = profile
        self.canDelete = canDelete
        self.onDelete = onDelete
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        HStack {
            TextField(
                text: $name,
                prompt: Text("e.g. Work")
            ) {
                Text("Profile name")
            }
            .labelsHidden()
            .onSubmit { TextInputComposition.performUnlessActive(saveName) }
            HStack(spacing: 8) {
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Profile color for \(profile.name)")
                ProfileColorPalette(selection: profileColorBinding)
            }
            Button {
                profileManager.requestClearBrowsingData(profile.id)
            } label: {
                Image(systemSymbol: .eraser)
            }
            .buttonStyle(.borderless)
            .help("Clear Browsing Data…")
            .accessibilityLabel("Clear Browsing Data for \(profile.name)")

            if profile.webProfileStore != .default {
                Button(role: .destructive, action: onDelete) {
                    Image(systemSymbol: .trash)
                }
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .help(canDelete ? "Delete Profile" : "Close this Profile’s windows before deleting it")
                .accessibilityLabel("Delete Profile \(profile.name)")
            } else {
                Button {
                } label: {
                    Image(systemSymbol: .trash)
                }
                .buttonStyle(.borderless)
                .disabled(true)
                .help("Default Profile (Personal) cannot be deleted")
                .accessibilityLabel("Default Profile (Personal) cannot be deleted")
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding {
            profileDisplayColor(for: profileColorBinding.wrappedValue)
        } set: { color in
            guard let profileColor = profileColor(from: color) else { return }
            _ = profileManager.updateProfile(profile.id, color: profileColor)
        }
    }

    private var profileColorBinding: Binding<ProfileColor> {
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
