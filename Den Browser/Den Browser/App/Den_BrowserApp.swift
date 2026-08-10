import AppKit
import SwiftUI

@main
struct Den_BrowserApp: App {
    @State private var preferences: AppPreferences
    @State private var sheetNavigation: SheetNavigationManager
    @State private var profileManager: ProfileManager
    @State private var keyboardController = KeyboardController()
    @State private var openSettingsCoordinator = OpenSettingsCoordinator()

    init() {
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
            websiteDataStore: configuration.websiteDataStore)
        _profileManager = State(initialValue: manager)
    }

    var body: some Scene {
        WindowGroup("Den Browser", for: UUID.self) { $profileID in
            ProfileWindowView(profileID: profileID)
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
            profileManager.personalProfileID
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            DenCommands(
                profileManager: profileManager,
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
    let openSettingsCoordinator: OpenSettingsCoordinator

    @FocusedValue(\.denStore) private var store
    @FocusedValue(\.profileID) private var profileID
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .saveItem) {
            if store == nil {
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command])
            } else {
                Button("Remove Board") { store?.performAppAction(.removeBoard) }
                    .keyboardShortcut("w", modifiers: [.command])
                    .disabled(
                        store?.focusedDesk?.focusedBoardID == nil
                            || store?.hasPendingConfirmation == true)
                Button("Close Profile Window") {
                    if let profileID {
                        dismissWindow(value: profileID)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(store?.hasPendingConfirmation == true)
            }
        }

        CommandMenu("Profile") {
            ForEach(profileManager.profiles) { profile in
                Button(profile.name) {
                    openWindow(value: profile.id)
                }
            }

            Divider()

            Button("Open Profile…") {
                profileManager.openProfilePanelProfileID = profileID
            }
            .keyboardShortcut("p", modifiers: [.control, .command])

            Button("Clear Browsing Data…") {
                let targetID = profileID ?? profileManager.personalProfileID
                profileManager.clearBrowsingDataProfileID = targetID
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])

            SettingsLink { Text("New Profile…") }
            SettingsLink { Text("Manage Profiles…") }
        }

        CommandMenu("Den") {
            Button("Toggle Den Mode") { store?.performAppAction(.toggleDenMode) }
                .disabled(store == nil)
            Button("Open Board") { store?.performAppAction(.showOpenBoardPanel) }
                .keyboardShortcut("t", modifiers: [.command])
                .disabled(store == nil)
            Button("Edit Focused Board Link") { store?.performAppAction(.showEditBoardLinkPanel) }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(store?.focusedBoard?.isTerminal != false)
            Button("New Desk") { store?.performAppAction(.showNewDeskPanel) }
                .disabled(store?.canCreateDesk != true)
            Button("Save Desk as Preset…") { store?.performAppAction(.showSaveDeskPresetPanel) }
                .disabled(store?.focusedDesk?.boards.isEmpty != false)
            Button("Capture Current Sheet Screenshot…") {
                store?.performAppAction(.captureCurrentSheet)
            }
            .disabled(store?.focusedBoard?.isTerminal != false)
            Menu("Export") {
                Button("Save Desk Links as Markdown…") {
                    store?.exportFocusedDeskLinks()
                }
                .disabled(store?.canExportFocusedDeskLinks != true)

                Button("Copy Desk Links as Markdown") {
                    store?.copyFocusedDeskLinks()
                }
                .disabled(store?.canExportFocusedDeskLinks != true)

                Divider()

                Button("Capture Focused Desk Screenshot…") {
                    store?.performAppAction(.captureFocusedDesk)
                }
                .disabled(
                    store?.focusedDesk?.boards.isEmpty != false
                        || store?.focusedDesk?.boards.contains(where: \.isTerminal) == true)
            }
            .disabled(store == nil)
            Button("Toggle Overview") { store?.toggleOverview() }
                .disabled(store == nil)
            Button("Toggle Zen View") { store?.performAppAction(.toggleZenView) }
                .disabled(store == nil)
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
            Button("Toggle Drawer") { store?.performAppAction(.toggleDrawer) }
                .disabled(store == nil)

            Divider()

            Menu("Resize Boards to Fit") {
                ForEach(1...9, id: \.self) { count in
                    Button(count == 1 ? "1 Board" : "\(count) Boards") {
                        store?.performAppAction(.resizeFocusedDeskBoards(count))
                    }
                    .disabled(store?.canResizeFocusedDeskBoards(toFit: count) != true)
                }
            }
            .disabled(store == nil)

            Divider()

            Button("Remove Board") { store?.performAppAction(.removeBoard) }
                .disabled(store == nil)
            Button("Restore Removed Board") { store?.performAppAction(.restoreBoard) }
                .disabled(store?.recentlyRemovedBoard == nil)
            Button("Delete Desk") { store?.performAppAction(.deleteDesk) }
                .disabled(store?.canDeleteFocusedDesk != true)

            Divider()

            Button("Reload Current Sheet") { store?.performAppAction(.reloadFocusedBoard) }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store?.focusedBoard?.isTerminal != false)
            Button("Hard Reload Current Sheet") { store?.performAppAction(.reloadFocusedBoardFromOrigin) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store?.focusedBoard?.isTerminal != false)
            Button("Reload Focused Desk Sheets") { store?.performAppAction(.reloadFocusedDeskSheets) }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(store?.focusedDesk?.boards.allSatisfy(\.isTerminal) != false)

            Divider()

            Button("Reset Den") { store?.requestResetDenConfirmation() }
                .disabled(store == nil || store?.hasPendingConfirmation == true)
        }
    }
}
