import SwiftUI

struct DenHeader: View {
    let profile: ProfileState

    @Environment(DenStore.self) private var store

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            DeskSwitcher(profileColor: profile.color.color)
                .frame(maxWidth: .infinity)
                .allowsHitTesting(store.temporaryContext == nil)
                .accessibilityHidden(store.temporaryContext != nil)

            if !store.isOverviewPresented {
                DenHeaderControls(profile: profile)
            }
        }
        .frame(height: DenLayout.denHeaderHeight)
    }
}

struct DenHeaderControls: View {
    let profile: ProfileState

    @Environment(DenStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            if store.focusedDesk?.boards.isEmpty == false {
                SaveDeskPresetButton()
            }

            ProfileChip(profile: profile)
        }
        .padding(.trailing, DenLayout.chromeHorizontalPadding)
    }
}

private struct SaveDeskPresetButton: View {
    @Environment(DenStore.self) private var store

    var body: some View {
        Button {
            store.showSaveDeskPresetPanel()
        } label: {
            Image(systemName: "bookmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .tint(.secondary)
        .fixedSize()
        .accessibilityLabel("Save Desk as Preset")
        .help("Save Desk as Preset")
    }
}

private struct ProfileChip: View {
    let profile: ProfileState

    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { item in
                Button {
                    openWindow(value: item.id)
                } label: {
                    Label(item.name, systemImage: item.id == profile.id ? "checkmark" : "person.crop.circle")
                }
            }

            Divider()

            Button("Open Profile…") {
                profileManager.openProfilePanelProfileID = profile.id
            }
            .keyboardShortcut("p", modifiers: [.control, .command])

            Button("Clear Browsing Data…") {
                profileManager.clearBrowsingDataProfileID = profile.id
            }

            SettingsLink {
                Text("New Profile…")
            }
            SettingsLink {
                Text("Manage Profiles…")
            }
        } label: {
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .tint(.secondary)
        .fixedSize()
        .accessibilityLabel("Profile: \(profile.name)")
        .help("Profile: \(profile.name)")
    }
}
