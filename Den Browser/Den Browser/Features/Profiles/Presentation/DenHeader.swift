import DenDesign
import DenDomain
import SFSafeSymbols
import SwiftUI

struct DenHeader: View {
    let profile: ProfileState
    let windowID: UUID

    @Environment(DenViewModel.self) private var viewModel
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        DeskSwitcher(
            profileColor: profileDisplayColor(for: profile.color),
            canOpenInNewWindow: {
                profileManager.canOpenDeskInNewWindow(
                    $0,
                    profileID: profile.id,
                    sourceWindowID: windowID)
            },
            isPresentedInAnotherWindow: {
                profileManager.isDeskPresentedInAnotherWindow(
                    $0,
                    profileID: profile.id,
                    excludingWindowID: windowID)
            },
            onOpenInNewWindow: { deskID in
                guard
                    let route = profileManager.routeForOpeningDesk(
                        deskID,
                        profileID: profile.id,
                        sourceWindowID: windowID)
                else { return }
                openWindow(value: route)
            }
        )
        .frame(maxWidth: .infinity)
        .allowsHitTesting(viewModel.temporaryContext == nil)
        .accessibilityHidden(viewModel.temporaryContext != nil)
        .frame(height: DenLayout.denHeaderHeight)
    }
}

struct DenHeaderControls: ToolbarContent {
    let profile: ProfileState
    let windowID: UUID

    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if !viewModel.isOverviewPresented {
            ToolbarSpacer(.flexible)
            ToolbarItemGroup(placement: .automatic) {
                NotificationButton()

                if store.focusedDesk?.boards.isEmpty == false {
                    SaveDeskPresetButton {
                        viewModel.showSaveDeskPresetPanel()
                    }
                }

                ProfileChip(profile: profile, windowID: windowID)
            }
        }
    }
}

private struct NotificationButton: View {
    @Environment(DenStore.self) private var store
    @Environment(DenViewModel.self) private var viewModel

    var body: some View {
        Button {
            viewModel.toggleNotificationList()
        } label: {
            Label {
                Text("Notifications")
            } icon: {
                Image(systemSymbol: store.unreadNotificationCount > 0 ? .bellBadge : .bell)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .tint(.secondary)
        .disabled(viewModel.temporaryContext != nil)
        .accessibilityLabel("Notifications")
        .accessibilityValue(
            store.unreadNotificationCount > 0
                ? "\(store.unreadNotificationCount) unread"
                : "No unread notifications"
        )
        .help("Notifications")
    }
}

private struct SaveDeskPresetButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label {
                Text("Save Desk as Preset")
            } icon: {
                Image(systemSymbol: .bookmark)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .tint(.secondary)
        .accessibilityLabel("Save Desk as Preset")
        .help("Save Desk as Preset")
    }
}

private struct ProfileChip: View {
    let profile: ProfileState
    let windowID: UUID

    @Environment(DenViewModel.self) private var viewModel
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            ForEach(profileManager.profiles) { item in
                Button {
                    if !profileManager.activateWindow(for: item.id) {
                        openWindow(value: ProfileWindowRoute(profileID: item.id))
                    }
                } label: {
                    Label(item.name, systemSymbol: item.id == profile.id ? .checkmark : .personCropCircle)
                }
            }

            Divider()

            Button("Open Profile…") {
                viewModel.setTemporaryContext(.profilePicker)
            }
            .keyboardShortcut("p", modifiers: [.control, .command])

            Button("Clear Browsing Data…") {
                profileManager.clearBrowsingDataProfileID = profile.id
                profileManager.clearBrowsingDataWindowID = windowID
            }

            SettingsLink {
                Text("New Profile…")
            }
            SettingsLink {
                Text("Manage Profiles…")
            }
        } label: {
            Label {
                Text("Profile")
            } icon: {
                Image(systemSymbol: .personFill)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .tint(.secondary)
        .accessibilityLabel("Profile: \(profile.name)")
        .help("Profile: \(profile.name)")
    }
}
