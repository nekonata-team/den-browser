import SFSafeSymbols
import SwiftUI

struct DenHeader: View {
    let profile: ProfileState
    let windowID: UUID

    @Environment(DenStore.self) private var store
    @Environment(ProfileManager.self) private var profileManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            DeskSwitcher(
                profileColor: profile.color.color,
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
            .allowsHitTesting(store.temporaryContext == nil)
            .accessibilityHidden(store.temporaryContext != nil)

            if !store.isOverviewPresented {
                DenHeaderControls(profile: profile, windowID: windowID)
            }
        }
        .frame(height: DenLayout.denHeaderHeight)
    }
}

struct DenHeaderControls: View {
    let profile: ProfileState
    let windowID: UUID

    @Environment(DenStore.self) private var store
    @Environment(ProfileManager.self) private var profileManager

    var body: some View {
        HStack(spacing: 8) {
            if profileManager.isPrivateDen {
                PrivateDenBadge(color: profile.color.color)
            }

            NotificationButton()

            if store.focusedDesk?.boards.isEmpty == false {
                SaveDeskPresetButton()
            }

            ProfileChip(profile: profile, windowID: windowID)
        }
        .padding(.trailing, DenLayout.chromeHorizontalPadding)
    }
}

private struct PrivateDenBadge: View {
    let color: Color

    var body: some View {
        Label("Private", systemSymbol: .lock)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Private Den")
            .help("Private Den")
    }
}

private struct NotificationButton: View {
    @Environment(DenStore.self) private var store

    var body: some View {
        Button {
            store.toggleNotificationList()
        } label: {
            Image(systemSymbol: store.unreadNotificationCount > 0 ? .bellBadge : .bell)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .tint(.secondary)
        .fixedSize()
        .disabled(store.temporaryContext != nil)
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
    @Environment(DenStore.self) private var store

    var body: some View {
        Button {
            store.showSaveDeskPresetPanel()
        } label: {
            Image(systemSymbol: .bookmark)
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
    let windowID: UUID

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
                profileManager.openProfilePanelProfileID = profile.id
                profileManager.openProfilePanelWindowID = windowID
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
            Image(systemSymbol: .personFill)
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
