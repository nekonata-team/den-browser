import DenDomain
import DenModels
import SFSafeSymbols
import SwiftUI

public struct DenHeader<ProfileMenu: View>: View {
    private let profileColor: Color
    private let canOpenInNewWindow: (DeskID) -> Bool
    private let isPresentedInAnotherWindow: (DeskID) -> Bool
    private let onOpenInNewWindow: (DeskID) -> Void
    private let onNotificationKeyPress: (KeyPress) -> KeyPress.Result
    private let restoreInput: () -> Void
    private let profileMenu: ProfileMenu
    @Environment(DenWindowModel.self) private var windowModel

    public init(
        profileColor: Color, canOpenInNewWindow: @escaping (DeskID) -> Bool,
        isPresentedInAnotherWindow: @escaping (DeskID) -> Bool, onOpenInNewWindow: @escaping (DeskID) -> Void,
        onNotificationKeyPress: @escaping (KeyPress) -> KeyPress.Result, restoreInput: @escaping () -> Void,
        @ViewBuilder profileMenu: () -> ProfileMenu
    ) {
        self.profileColor = profileColor
        self.canOpenInNewWindow = canOpenInNewWindow
        self.isPresentedInAnotherWindow = isPresentedInAnotherWindow
        self.onOpenInNewWindow = onOpenInNewWindow
        self.onNotificationKeyPress = onNotificationKeyPress
        self.restoreInput = restoreInput
        self.profileMenu = profileMenu()
    }

    public var body: some View {
        DeskSwitcher(
            profileColor: profileColor, canOpenInNewWindow: canOpenInNewWindow,
            isPresentedInAnotherWindow: isPresentedInAnotherWindow, onOpenInNewWindow: onOpenInNewWindow
        )
        .frame(maxWidth: .infinity)
        .allowsHitTesting(windowModel.temporaryContext == nil)
        .accessibilityHidden(windowModel.temporaryContext != nil)
        .frame(height: DenLayout.denHeaderHeight)
        .toolbar {
            DenHeaderControls(
                profileColor: profileColor, onNotificationKeyPress: onNotificationKeyPress,
                restoreInput: restoreInput, profileMenu: profileMenu)
        }
    }
}

private struct DenHeaderControls<ProfileMenu: View>: ToolbarContent {
    let profileColor: Color
    let onNotificationKeyPress: (KeyPress) -> KeyPress.Result
    let restoreInput: () -> Void
    let profileMenu: ProfileMenu

    @Environment(DenWindowModel.self) private var windowModel

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if !windowModel.isOverviewPresented {
            ToolbarItemGroup(placement: .principal) {
                OverviewButton()
                DrawerButton()
            }
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) {
                UniversalSearchButton()
            }
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .automatic) {
                NotificationButton(
                    profileColor: profileColor, onKeyPress: onNotificationKeyPress, restoreInput: restoreInput)

                SaveDeskPresetButton {
                    windowModel.showSaveDeskPresetPanel()
                }
                .disabled(
                    windowModel.focusedDesk?.boards.isEmpty != false
                        || windowModel.temporaryContext != nil)

                profileMenu
            }
        }
    }
}

private struct OverviewButton: View {
    @Environment(DenWindowModel.self) private var windowModel

    var body: some View {
        Button {
            windowModel.toggleOverview()
        } label: {
            Label {
                Text("Overview")
            } icon: {
                Image(systemSymbol: .squareGrid2x2)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .tint(windowModel.isOverviewPresented ? .accentColor : .secondary)
        .disabled(windowModel.temporaryContext != nil && !windowModel.isOverviewPresented)
        .help("Overview")
        .accessibilityLabel("Overview")
        .accessibilityIdentifier("overview-button")
    }
}

private struct DrawerButton: View {
    @Environment(DenWindowModel.self) private var windowModel

    var body: some View {
        Button {
            windowModel.toggleDrawer()
        } label: {
            Label {
                Text("Drawer")
            } icon: {
                Image(systemSymbol: .tray)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .tint(windowModel.isDrawerOpen ? .accentColor : .secondary)
        .disabled(windowModel.temporaryContext != nil && !windowModel.isDrawerOpen)
        .help("Drawer")
        .accessibilityLabel("Drawer")
        .accessibilityIdentifier("drawer-button")
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
            .padding(.horizontal, 4)
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
    let onKeyPress: (KeyPress) -> KeyPress.Result
    let restoreInput: () -> Void

    @FocusState private var isNotificationListFocused: Bool
    @Environment(DenWindowModel.self) private var windowModel

    var body: some View {
        Button {
            windowModel.toggleNotificationList()
        } label: {
            Label {
                Text("Notifications")
            } icon: {
                Image(systemSymbol: windowModel.notificationList.unreadCount > 0 ? .bellBadge : .bell)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .tint(.secondary)
        .disabled(windowModel.temporaryContext != nil)
        .accessibilityLabel("Notifications")
        .accessibilityValue(
            windowModel.notificationList.unreadCount > 0
                ? "\(windowModel.notificationList.unreadCount) unread"
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
                    onKeyPress(press)
                }
                .onDisappear {
                    if windowModel.temporaryContext == nil, !windowModel.hasPendingConfirmation {
                        restoreInput()
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
        .accessibilityIdentifier("save-desk-preset-button")
        .help("Save Desk as Preset")
    }
}

public struct ProfileMenu: View {
    let profile: ProfileState
    let profiles: [ProfileState]
    let openProfile: (ProfileID) -> Void
    let clearBrowsingData: () -> Void

    public init(
        profile: ProfileState, profiles: [ProfileState], openProfile: @escaping (ProfileID) -> Void,
        clearBrowsingData: @escaping () -> Void
    ) {
        self.profile = profile
        self.profiles = profiles
        self.openProfile = openProfile
        self.clearBrowsingData = clearBrowsingData
    }

    @Environment(DenWindowModel.self) private var windowModel

    public var body: some View {
        Menu {
            ForEach(profiles) { item in
                Button {
                    openProfile(item.id)
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
                clearBrowsingData()
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
