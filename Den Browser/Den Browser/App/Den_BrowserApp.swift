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
                .onAppear {
                    keyboardController.start(profileManager: profileManager, preferences: preferences)
                }
        } defaultValue: {
            profileManager.personalProfileID
        }
        .handlesExternalEvents(matching: ["*"])
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
                Button("Remove Board") { store?.removeFocusedBoard() }
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
            Button("Toggle Den Mode") { store?.toggleDenMode() }
                .disabled(store == nil)
            Button("Open Board") { store?.showOpenBoardPanel() }
                .keyboardShortcut("t", modifiers: [.command])
                .disabled(store == nil)
            Button("Edit Focused Board Link") { store?.showEditBoardLinkPanel() }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(store?.focusedBoard == nil)
            Button("New Desk") { store?.showNewDeskPanel() }
                .disabled(store?.canCreateDesk != true)
            Button("Save Desk as Preset…") { store?.showSaveDeskPresetPanel() }
                .disabled(store?.focusedDesk?.boards.isEmpty != false)
            Button("Capture Current Sheet Screenshot…") {
                store?.captureFocusedSheetScreenshot()
            }
            .disabled(store?.focusedBoard == nil)
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
                    store?.captureFocusedDeskScreenshot()
                }
                .disabled(store?.focusedDesk?.boards.isEmpty != false)
            }
            .disabled(store == nil)
            Button("Toggle Overview") { store?.toggleOverview() }
                .disabled(store == nil)
            Button("Toggle Zen View") { store?.toggleZenView() }
                .disabled(store == nil)
            Button("Keyboard Shortcuts…") { store?.showKeyboardShortcuts() }
                .disabled(store == nil)
            SettingsLink()
                .keyboardShortcut(",", modifiers: [])
                .disabled(store?.isDenMode != true || store?.temporaryContext != nil)
            Button("Toggle Drawer") { store?.toggleDrawer() }
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
            Button("Hard Reload Current Sheet") { store?.reloadFocusedBoardFromOrigin() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store == nil)
            Button("Reload Focused Desk Sheets") { store?.reloadFocusedDeskSheets() }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(store?.focusedDesk?.boards.isEmpty != false)

            Divider()

            Button("Reset Den") { store?.requestResetDenConfirmation() }
                .disabled(store == nil || store?.hasPendingConfirmation == true)
        }
    }
}
