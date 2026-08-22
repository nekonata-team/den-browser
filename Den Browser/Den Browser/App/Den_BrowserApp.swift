import Sparkle
import SwiftUI

@main
struct Den_BrowserApp: App {
    private let updaterController: SPUStandardUpdaterController
    @State private var preferences: AppPreferences
    @State private var sheetNavigation: SheetNavigationManager
    @State private var profileManager: ProfileManager
    @State private var keyboardController = KeyboardController()
    @State private var openSettingsCoordinator = OpenSettingsCoordinator()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        let configuration = AppConfiguration.current()
        let preferences = AppPreferences(defaults: configuration.defaults)
        let sheetNavigation = SheetNavigationManager(defaults: configuration.defaults)
        _preferences = State(initialValue: preferences)
        _sheetNavigation = State(initialValue: sheetNavigation)
        let manager = ProfileManager(
            directoryURL: configuration.profileDirectoryURL,
            sheetNavigation: sheetNavigation,
            preferences: preferences,
            initialProfile: configuration.initialProfile,
            websiteDataStore: configuration.websiteDataStore,
            webExtensionDescriptors: [
                BundledWebExtensionDescriptor(
                    identifier: "com.denbrowser.ubolite",
                    resourceName: "uBOLite.safari.zip",
                    preapproveRequestedAccess: true)
            ])
        _profileManager = State(initialValue: manager)
    }

    var body: some Scene {
        WindowGroup("Den Browser", for: ProfileWindowRoute.self) { $route in
            ProfileWindowView(route: route)
                .environment(profileManager)
                .environment(preferences)
                .environment(\.colorScheme, .dark)
                .containerBackground(.clear, for: .window)
                .background {
                    KeyboardControllerBridge(
                        controller: keyboardController,
                        profileManager: profileManager,
                        preferences: preferences,
                        openSettingsCoordinator: openSettingsCoordinator)
                }
        } defaultValue: {
            ProfileWindowRoute(
                windowID: profileManager.personalProfileID,
                profileID: profileManager.personalProfileID)
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            DenCommands(
                profileManager: profileManager,
                updaterController: updaterController,
                openSettingsCoordinator: openSettingsCoordinator)
        }

        Settings {
            SettingsView()
                .environment(profileManager)
                .environment(preferences)
                .environment(sheetNavigation)
        }
    }
}

private struct KeyboardControllerBridge: View {
    @Environment(\.openSettings) private var openSettings

    let controller: KeyboardController
    let profileManager: ProfileManager
    let preferences: AppPreferences
    let openSettingsCoordinator: OpenSettingsCoordinator

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                openSettingsCoordinator.action = { openSettings() }
                controller.start(
                    profileManager: profileManager,
                    preferences: preferences,
                    openSettings: { openSettingsCoordinator.open() })
            }
    }
}

@MainActor
private final class OpenSettingsCoordinator {
    var action: () -> Void = {}

    func open() {
        action()
    }
}

private struct DenCommands: Commands {
    let profileManager: ProfileManager
    let updaterController: SPUStandardUpdaterController
    let openSettingsCoordinator: OpenSettingsCoordinator

    @FocusedValue(\.denStore) private var store
    @FocusedValue(\.profileID) private var profileID
    @FocusedValue(\.profileWindowID) private var profileWindowID
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updaterController.checkForUpdates(nil)
            }
        }

        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .saveItem) {
            if store == nil {
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command])
            } else {
                Button("Close Profile Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(store?.hasPendingConfirmation == true)
            }
        }

        CommandMenu("Profile") {
            ForEach(profileManager.profiles) { profile in
                Button(profile.name) {
                    if !profileManager.activateWindow(for: profile.id) {
                        openWindow(value: ProfileWindowRoute(profileID: profile.id))
                    }
                }
            }

            Divider()

            Menu("Manage Profiles") {
                Button("Open Profile…") {
                    profileManager.openProfilePanelProfileID = profileID
                    profileManager.openProfilePanelWindowID = profileWindowID
                }
                .keyboardShortcut("p", modifiers: [.control, .command])

                SettingsLink { Text("New Profile…") }
                SettingsLink { Text("Manage Profiles…") }
            }

            Button("Clear Browsing Data…") {
                let targetID = profileID ?? profileManager.personalProfileID
                profileManager.clearBrowsingDataProfileID = targetID
                profileManager.clearBrowsingDataWindowID = profileWindowID
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }

        CommandMenu("Den") {
            Button("Toggle Den Mode") { store?.performAppAction(.toggleDenMode) }
                .disabled(store == nil)

            Menu("Board") {
                Button("Open Board") { store?.performAppAction(.showOpenBoardPanel) }
                    .keyboardShortcut("t", modifiers: [.command])
                    .disabled(store == nil)
                Button("Edit Focused Board Link") {
                    store?.performAppAction(.showEditBoardLinkPanel)
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(store?.focusedBoard?.isTerminal != false)

                Divider()

                Button("Reload Current Sheet") { store?.performAppAction(.reloadFocusedBoard) }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(store?.focusedBoard?.isTerminal != false)
                Button("Hard Reload Current Sheet") {
                    store?.performAppAction(.reloadFocusedBoardFromOrigin)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store?.focusedBoard?.isTerminal != false)
                Button("Capture Current Sheet Screenshot…") {
                    store?.performAppAction(.captureCurrentSheet)
                }
                .disabled(store?.focusedBoard?.isTerminal != false)

                Divider()

                Button("Remove Board") { store?.performAppAction(.removeBoard) }
                    .keyboardShortcut("w", modifiers: [.command])
                    .disabled(
                        store?.focusedDesk?.focusedBoardID == nil
                            || store?.hasPendingConfirmation == true)
                Button("Restore Removed Board") { store?.performAppAction(.restoreBoard) }
                    .disabled(store?.recentlyRemovedBoards.isEmpty ?? true)
            }

            Button("zmx Sessions…") { store?.showZmxSessions() }
                .disabled(store?.zmxClient.isConfigured != true)

            Menu("Drawer") {
                Button("Restore Discarded Drawer Item") {
                    store?.performAppAction(.restoreDiscardedDrawerItem)
                }
                .disabled(store?.recentlyDiscardedDrawerItems.isEmpty ?? true)
            }

            Menu("Desk") {
                Button("New Desk") { store?.performAppAction(.showNewDeskPanel) }
                    .disabled(store?.canCreateDesk != true)
                Button("Save Desk as Preset…") { store?.performAppAction(.showSaveDeskPresetPanel) }
                    .disabled(store?.focusedDesk?.boards.isEmpty != false)

                Menu("Export") {
                    Button("Save Desk Links as Markdown…") {
                        store?.exportFocusedDeskLinks()
                    }
                    .disabled(store?.canExportFocusedDeskLinks != true)

                    Button("Copy Desk Links as Markdown") {
                        store?.copyFocusedDeskLinks()
                    }
                    .disabled(store?.canExportFocusedDeskLinks != true)
                }
                .disabled(store == nil)

                Button("Capture Focused Desk Screenshot…") {
                    store?.performAppAction(.captureFocusedDesk)
                }
                .disabled(
                    store?.focusedDesk?.boards.isEmpty != false
                        || store?.focusedDesk?.boards.contains(where: \.isTerminal) == true)

                Menu("Resize Boards to Fit") {
                    ForEach(1...9, id: \.self) { count in
                        Button(count == 1 ? "1 Board" : "\(count) Boards") {
                            store?.performAppAction(.resizeFocusedDeskBoards(count))
                        }
                        .disabled(store?.canResizeFocusedDeskBoards(toFit: count) != true)
                    }
                }
                .disabled(store == nil)

                Button("Reload Focused Desk Sheets") {
                    store?.performAppAction(.reloadFocusedDeskSheets)
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(store?.focusedDesk?.boards.allSatisfy(\.isTerminal) != false)

                Divider()

                Button("Delete Desk") { store?.performAppAction(.deleteDesk) }
                    .disabled(store?.canDeleteFocusedDesk != true)
            }

            Menu("Presentation") {
                Button("Toggle Overview") { store?.toggleOverview() }
                    .disabled(store == nil)
                Button("Toggle Zen View") { store?.performAppAction(.toggleZenView) }
                    .disabled(store == nil)
                Toggle(
                    "Focus Mode",
                    isOn: Binding(
                        get: { store?.isFocusModePresented == true },
                        set: { isPresented in
                            guard isPresented != (store?.isFocusModePresented ?? false) else { return }
                            store?.performAppAction(.toggleFocusMode)
                        })
                )
                .disabled(store == nil || store?.temporaryContext != nil)
                Button("Toggle Drawer") { store?.performAppAction(.toggleDrawer) }
                    .disabled(store == nil)
            }

            Button("Keyboard Shortcuts…") { store?.performAppAction(.showKeyboardShortcuts) }
                .disabled(store == nil)
            Button("Settings…") {
                AppActionHandler.perform(
                    .openSettings,
                    store: store,
                    openSettings: { openSettingsCoordinator.open() })
            }
            .keyboardShortcut(",", modifiers: [])
            .disabled(store?.isDenMode != true || store?.temporaryContext != nil)

            Divider()
            Button("Reset Den") { store?.requestResetDenConfirmation() }
                .disabled(store == nil || store?.hasPendingConfirmation == true)
        }
    }
}
