import DenDesign
import DenDomain
import DenPresentationModels
import SFSafeSymbols
import SwiftUI

struct DenHeader: View {
    let profile: ProfileState
    let windowID: UUID

    @Environment(DenWindowModel.self) private var windowModel
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
        .allowsHitTesting(windowModel.temporaryContext == nil)
        .accessibilityHidden(windowModel.temporaryContext != nil)
        .frame(height: DenLayout.denHeaderHeight)
        .toolbar {
            DenHeaderControls(profile: profile, windowID: windowID)
        }
    }
}

struct DenHeaderControls: ToolbarContent {
    let profile: ProfileState
    let windowID: UUID

    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if !windowModel.isOverviewPresented {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) {
                UniversalSearchButton()
            }
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .automatic) {
                NotificationButton(profileColor: profileDisplayColor(for: profile.color))

                if controller.focusedDesk?.boards.isEmpty == false {
                    SaveDeskPresetButton {
                        windowModel.showSaveDeskPresetPanel()
                    }
                }

                ProfileChip(profile: profile, windowID: windowID)
            }
        }
    }
}

private struct UniversalSearchButton: View {
    @Environment(DenWindowModel.self) private var windowModel

    var body: some View {
        Button {
            windowModel.showUniversalSearch()
        } label: {
            Label {
                HStack(spacing: 8) {
                    Text("Search")
                    Text("⌘P")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } icon: {
                Image(systemSymbol: .magnifyingglass)
            }
        }
        .labelStyle(.titleAndIcon)
        .tint(.secondary)
        .disabled(windowModel.temporaryContext != nil)
        .help("Universal Search (⌘P)")
        .accessibilityIdentifier("universal-search-button")
    }
}

private struct NotificationButton: View {
    let profileColor: Color

    @FocusState private var isNotificationListFocused: Bool
    @Environment(DenController.self) private var controller
    @Environment(DenWindowModel.self) private var windowModel

    var body: some View {
        Button {
            windowModel.toggleNotificationList()
        } label: {
            Label {
                Text("Notifications")
            } icon: {
                Image(systemSymbol: controller.unreadNotificationCount > 0 ? .bellBadge : .bell)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .tint(.secondary)
        .disabled(windowModel.temporaryContext != nil)
        .accessibilityLabel("Notifications")
        .accessibilityValue(
            controller.unreadNotificationCount > 0
                ? "\(controller.unreadNotificationCount) unread"
                : "No unread notifications"
        )
        .help("Notifications")
        .popover(
            isPresented: Binding(
                get: { windowModel.isNotificationListPresented && !windowModel.isZenViewPresented },
                set: { if !$0 { windowModel.closeNotificationList() } }
            ),
            arrowEdge: .bottom
        ) {
            NotificationListView(profileColor: profileColor)
                .environment(windowModel.notificationList)
                .focusable(interactions: .edit)
                .focusEffectDisabled()
                .focused($isNotificationListFocused)
                .onAppear { isNotificationListFocused = true }
                .onKeyPress(phases: [.down, .repeat]) { press in
                    KeyboardController.handleNotificationKeyPress(
                        press, controller: controller, windowModel: windowModel)
                }
                .onDisappear {
                    if windowModel.temporaryContext == nil, !windowModel.hasPendingConfirmation {
                        controller.restoreFocusedFirstResponder()
                    }
                }
        }
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

    @Environment(DenWindowModel.self) private var windowModel
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
                windowModel.setTemporaryContext(.profilePicker)
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
