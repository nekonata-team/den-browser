import SwiftUI

@main
struct Den_BrowserApp: App {
    @State private var store: DenStore
    @State private var keyboardController = KeyboardController()

    init() {
        let sheetNavigation = SheetNavigationManager()
        _store = State(initialValue: DenStore(sheetNavigation: sheetNavigation))
    }

    var body: some Scene {
        WindowGroup("Den Browser") {
            ContentView()
                .environment(store)
                .environment(\.colorScheme, .dark)
                .containerBackground(.clear, for: .window)
                .onAppear {
                    keyboardController.start(store: store)
                }
                .onDisappear {
                    keyboardController.stop()
                }
        }
        .commands {
            CommandMenu("Den") {
                Button("Enter Den Mode") { store.enterDenMode() }
                Button("Open Board") { store.showOpenBoardPanel() }
                    .keyboardShortcut("t", modifiers: [.command])
                Button("New Desk") { store.showNewDeskPanel() }
                    .disabled(!store.canCreateDesk)
                Button("Toggle Overview") { store.toggleOverview() }

                Divider()

                Button("Cut Board") { store.cutFocusedBoard() }
                    .disabled(store.cutBoard != nil)
                Button("Place Cut Board") { store.placeCutBoard() }
                    .disabled(store.cutBoard == nil)
                Button("Restore Cut Board") { store.restoreCutBoard() }
                    .disabled(store.cutBoard == nil)
                Button("Delete Board") { store.closeFocusedBoard() }
                Button("Delete Empty Desk") { store.deleteFocusedDesk() }
                    .disabled(!store.canDeleteFocusedDesk)

                Divider()

                Button("Reload Current Sheet") { store.reloadFocusedBoard() }
                    .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Reset Den") { store.resetDen() }
            }
        }

        Settings {
            SettingsView()
                .environment(store.sheetNavigation)
        }
    }
}
