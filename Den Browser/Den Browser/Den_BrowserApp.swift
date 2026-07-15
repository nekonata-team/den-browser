import AppKit
import SwiftUI

@main
struct Den_BrowserApp: App {
    @State private var preferences: AppPreferences
    @State private var sheetNavigation: SheetNavigationManager
    @State private var profileManager: ProfileManager
    @State private var keyboardController = KeyboardController()

    init() {
        let preferences = AppPreferences()
        let sheetNavigation = SheetNavigationManager(preferences: preferences)
        _preferences = State(initialValue: preferences)
        _sheetNavigation = State(initialValue: sheetNavigation)
        _profileManager = State(
            initialValue: ProfileManager(sheetNavigation: sheetNavigation))
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
            Button("Toggle Overview") { store?.toggleOverview() }
                .disabled(store == nil)
            Button("Toggle Zen View") { store?.toggleZenView() }
                .disabled(store == nil)
            Button("Keyboard Shortcuts…") { store?.showKeyboardShortcuts() }
                .disabled(store == nil)

            Divider()

            Button("Hold Board") { store?.holdFocusedBoard() }
                .disabled(store?.heldBoard != nil || store == nil)
            Button("Place Held Board Right") { store?.placeHeldBoard() }
                .disabled(store?.heldBoard == nil)
            Button("Place Held Board Left") { store?.placeHeldBoard(beforeFocusedBoard: true) }
                .disabled(store?.heldBoard == nil)
            Button("Restore Held Board") { store?.restoreHeldBoard() }
                .disabled(store?.heldBoard == nil)
            Button("Delete Board") { store?.closeFocusedBoard() }
                .disabled(store == nil)
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
