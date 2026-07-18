import AppKit
import SwiftUI

@main
struct Den_BrowserApp: App {
    @State private var preferences: AppPreferences
    @State private var sheetNavigation: SheetNavigationManager
    @State private var profileManager: ProfileManager
    @State private var keyboardController = KeyboardController()

    init() {
        let configuration = AppConfiguration.current()
        let preferences = AppPreferences(defaults: configuration.defaults)
        if configuration.isUITesting {
            preferences.setMotionPreference(.reduced)
        }
        let sheetNavigation = SheetNavigationManager(preferences: preferences)
        _preferences = State(initialValue: preferences)
        _sheetNavigation = State(initialValue: sheetNavigation)
        _profileManager = State(
            initialValue: ProfileManager(
                directoryURL: configuration.profileDirectoryURL,
                sheetNavigation: sheetNavigation,
                initialProfile: configuration.initialProfile,
                websiteDataStore: configuration.websiteDataStore))
    }

    var body: some Scene {
        WindowGroup("Den Browser", for: UUID.self) { $profileID in
            ProfileWindowView(profileID: profileID)
                .environment(profileManager)
                .environment(preferences)
                .environment(\.colorScheme, .dark)
                .containerBackground(.clear, for: .window)
                .onAppear {
                    keyboardController.start(profileManager: profileManager, preferences: preferences)
                }
        } defaultValue: {
            profileManager.personalProfileID
        }
        .commands {
            DenCommands(profileManager: profileManager)
        }

        Settings {
            SettingsView()
                .environment(profileManager)
                .environment(preferences)
                .environment(sheetNavigation)
        }
    }
}

private struct DenCommands: Commands {
    let profileManager: ProfileManager

    @FocusedValue(\.denStore) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            if store == nil {
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command])
            } else {
                Button("Remove Board") { store?.removeFocusedBoard() }
                    .keyboardShortcut("w", modifiers: [.command])
                    .disabled(
                        store?.focusedDesk?.focusedBoardID == nil
                            || store?.hasPendingConfirmation == true)
                Button("Close Profile Window") { NSApp.keyWindow?.performClose(nil) }
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
                profileManager.openProfilePanelProfileID = profileManager.profileID(for: NSApp.keyWindow)
            }
            .keyboardShortcut("p", modifiers: [.control, .command])

            SettingsLink { Text("New Profile…") }
            SettingsLink { Text("Manage Profiles…") }
        }

        CommandMenu("Den") {
            Button("Toggle Den Mode") { store?.toggleDenMode() }
                .disabled(store == nil)
            Button("Open Board") { store?.showOpenBoardPanel() }
                .keyboardShortcut("t", modifiers: [.command])
                .disabled(store == nil)
            Button("New Desk") { store?.showNewDeskPanel() }
                .disabled(store?.canCreateDesk != true)
            Button("Save Desk as Preset…") { store?.showSaveDeskPresetPanel() }
                .disabled(store?.focusedDesk?.boards.isEmpty != false)
            Button("Toggle Overview") { store?.toggleOverview() }
                .disabled(store == nil)
            Button("Toggle Zen View") { store?.toggleZenView() }
                .disabled(store == nil)
            Button("Keyboard Shortcuts…") { store?.showKeyboardShortcuts() }
                .disabled(store == nil)

            Divider()

            Menu("Resize Boards to Fit") {
                ForEach(1...9, id: \.self) { count in
                    Button(count == 1 ? "1 Board" : "\(count) Boards") {
                        store?.resizeFocusedDeskBoards(toFit: count)
                    }
                    .disabled(store?.canResizeFocusedDeskBoards(toFit: count) != true)
                }
            }
            .disabled(store == nil)

            Divider()

            Button("Remove Board") { store?.removeFocusedBoard() }
                .disabled(store == nil)
            Button("Restore Removed Board") { store?.restoreRecentlyRemovedBoard() }
                .disabled(store?.recentlyRemovedBoard == nil)
            Button("Delete Desk") { store?.deleteFocusedDesk() }
                .disabled(store?.canDeleteFocusedDesk != true)

            Divider()

            Button("Reload Current Sheet") { store?.reloadFocusedBoard() }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store == nil)

            Divider()

            Button("Reset Den") { store?.resetDen() }
                .disabled(store == nil)
        }
    }
}
