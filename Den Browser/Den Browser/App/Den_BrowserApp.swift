import AppKit
import DenDomain
import Sparkle
import SwiftUI

@main
struct Den_BrowserApp: App {
    @NSApplicationDelegateAdaptor(DenApplicationDelegate.self) private var appDelegate
    private let updaterController = UpdaterControllerCoordinator()
    @State private var preferences: AppPreferences
    @State private var sheetNavigation: SheetNavigationManager
    @State private var profileManager: ProfileManager
    @State private var keyboardController = KeyboardController()
    @State private var openSettingsCoordinator = OpenSettingsCoordinator()

    init() {
        PerformanceTrace.mark("App.init start", category: "Launch")
        let configuration = AppConfiguration.current()
        let preferences = AppPreferences(defaults: configuration.defaults)
        let sheetNavigation = SheetNavigationManager(defaults: configuration.defaults)
        _preferences = State(initialValue: preferences)
        _sheetNavigation = State(initialValue: sheetNavigation)
        PerformanceTrace.mark("Preferences & Configuration initialized", category: "Launch")
        let manager = ProfileManager(
            directoryURL: configuration.profileDirectoryURL,
            sheetNavigation: sheetNavigation,
            preferences: preferences,
            initialProfile: configuration.initialProfile,
            isEphemeral: configuration.isEphemeral,
            websiteDataStore: configuration.websiteDataStore,
            ipcSocketPath: configuration.ipcSocketPath)
        _profileManager = State(initialValue: manager)
        appDelegate.profileManager = manager
        PerformanceTrace.mark("ProfileManager initialized", category: "Launch")
        DenIPCService.shared.start(profileManager: manager)
    }

    var body: some Scene {
        WindowGroup("Den Browser", for: ProfileWindowRoute.self) { $route in
            ProfileWindowView(
                route: route,
                startUpdater: { updaterController.start() },
                registerKeyboardWindow: { window, viewModel in
                    keyboardController.register(viewModel: viewModel, for: window)
                },
                unregisterKeyboardWindow: { window in
                    keyboardController.unregister(window: window)
                }
            )
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

@MainActor
private final class UpdaterControllerCoordinator {
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil)
        PerformanceTrace.mark("UpdaterController initialized after window presentation", category: "Launch")
    }

    func checkForUpdates() {
        start()
        controller?.checkForUpdates(nil)
    }
}

private struct DenCommands: Commands {
    let profileManager: ProfileManager
    let updaterController: UpdaterControllerCoordinator
    let openSettingsCoordinator: OpenSettingsCoordinator

    @FocusedValue(\.denViewModel) private var viewModel
    @FocusedValue(\.profileID) private var profileID
    @FocusedValue(\.profileWindowID) private var profileWindowID
    @Environment(\.openWindow) private var openWindow

    private var store: DenStore? { viewModel?.store }

    private func perform(_ action: AppAction) {
        AppActionHandler.perform(action, viewModel: viewModel)
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updaterController.checkForUpdates()
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
                .disabled(viewModel?.pendingConfirmation != nil)
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Board Activity") { perform(.overview(.toggleActivity)) }
                .keyboardShortcut(.escape, modifiers: [.shift])
                .disabled(
                    store == nil
                        || viewModel?.pendingConfirmation != nil
                        || viewModel?.isFullscreenActive == true)
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

            Button("Open Private Den") {
                PrivateDenLauncher.open()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Menu("Manage Profiles") {
                Button("Open Profile…") {
                    viewModel?.setTemporaryContext(.profilePicker)
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
            Button("Toggle Den Mode") { perform(.application(.toggleDenMode)) }
                .disabled(store == nil)

            Menu("Board") {
                Button("Open Board") { perform(.board(.showOpenPanel)) }
                    .keyboardShortcut("t", modifiers: [.command])
                    .disabled(store == nil)
                Button("Inspect Current Sheet") {
                    guard let board = store?.focusedBoard, board.isWeb else { return }
                    store?.createInspectionBoard(targetBoardID: board.id)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(store?.focusedBoard?.isWeb != true)
                Menu("Sheet Size") {
                    Button(
                        store?.focusedBoard?.isTerminal == true
                            ? "Increase Font Size" : "Increase Sheet Scale"
                    ) {
                        perform(.board(.increaseSheetSize))
                    }
                    .keyboardShortcut("=", modifiers: [.command, .shift])

                    Button(
                        store?.focusedBoard?.isTerminal == true
                            ? "Decrease Font Size" : "Decrease Sheet Scale"
                    ) {
                        perform(.board(.decreaseSheetSize))
                    }
                    .keyboardShortcut("-", modifiers: [.command])

                    Button(
                        store?.focusedBoard?.isTerminal == true
                            ? "Reset Font Size" : "Reset Sheet Scale"
                    ) {
                        perform(.board(.resetSheetSize))
                    }
                    .keyboardShortcut("0", modifiers: [.command])
                }
                .disabled(!(store?.focusedBoard?.isWeb == true || store?.focusedBoard?.isTerminal == true))
                Button("Edit Focused Board Link") {
                    perform(.board(.showEditLinkPanel))
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(store?.focusedBoard?.isWeb != true)

                Divider()

                Button("Reload Current Sheet") { perform(.board(.reload)) }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(store?.focusedBoard?.isWeb != true)
                Button("Hard Reload Current Sheet") {
                    perform(.board(.reloadFromOrigin))
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store?.focusedBoard?.isWeb != true)
                Button("Capture Current Sheet Screenshot…") {
                    perform(.board(.captureSheet))
                }
                .disabled(store?.focusedBoard?.isWeb != true)

                Divider()

                Button("Remove Board") { perform(.board(.remove)) }
                    .keyboardShortcut("w", modifiers: [.command])
                    .disabled(
                        store?.focusedDesk?.focusedBoardID == nil
                            || viewModel?.pendingConfirmation != nil)
                Button("Restore Removed Board") { perform(.board(.restore)) }
                    .disabled(store?.recentlyRemovedBoards.isEmpty ?? true)
            }

            Button("zmx Sessions…") { viewModel?.showZmxSessions() }
                .disabled(store?.zmxClient.isConfigured != true)

            Menu("Drawer") {
                Button("Restore Discarded Drawer Item") {
                    perform(.drawer(.restoreDiscardedItem))
                }
                .disabled(store?.recentlyDiscardedDrawerItems.isEmpty ?? true)
            }

            Menu("Desk") {
                Button("New Desk") { perform(.desk(.showNewPanel)) }
                    .disabled(store?.canCreateDesk != true)
                Button("Save Desk as Preset…") { perform(.desk(.showSavePresetPanel)) }
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

                Menu("Resize Boards to Fit") {
                    ForEach(1...9, id: \.self) { count in
                        Button(count == 1 ? "1 Board" : "\(count) Boards") {
                            perform(.desk(.resizeBoards(count)))
                        }
                        .disabled(viewModel?.canResizeFocusedDeskBoards(toFit: count) != true)
                    }
                }
                .disabled(store == nil)

                Button("Reload Focused Desk Sheets") {
                    perform(.desk(.reloadSheets))
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(store?.focusedDesk?.boards.contains(where: \.isWeb) != true)

                Divider()

                Button("Delete Desk") { perform(.desk(.delete)) }
                    .disabled(store?.canDeleteFocusedDesk != true)
            }

            Menu("Presentation") {
                Button("Toggle Overview") { viewModel?.toggleOverview() }
                    .disabled(store == nil)
                Button("Toggle Zen View") { perform(.application(.toggleZenView)) }
                    .disabled(store == nil)
                Toggle(
                    "Focus Mode",
                    isOn: Binding(
                        get: { viewModel?.isFocusModePresented == true },
                        set: { isPresented in
                            guard isPresented != (viewModel?.isFocusModePresented ?? false) else { return }
                            perform(.application(.toggleFocusMode))
                        })
                )
                .disabled(store == nil || viewModel?.temporaryContext != nil)
                Button("Toggle Drawer") { perform(.drawer(.toggle)) }
                    .disabled(store == nil)
            }

            Button("Keyboard Shortcuts…") { perform(.application(.showKeyboardShortcuts)) }
                .disabled(store == nil)
            Button("Settings…") {
                AppActionHandler.perform(
                    .application(.openSettings),
                    viewModel: viewModel,
                    openSettings: { openSettingsCoordinator.open() })
            }
            .keyboardShortcut(",", modifiers: [])
            .disabled(viewModel?.isDenMode != true || viewModel?.temporaryContext != nil)

            Divider()
            Button("Reset Den") { viewModel?.requestResetDenConfirmation() }
                .disabled(store == nil || viewModel?.pendingConfirmation != nil)
        }
    }

}

@MainActor
private final class DenApplicationDelegate: NSObject, NSApplicationDelegate {
    var profileManager: ProfileManager?

    func applicationWillTerminate(_ notification: Notification) {
        profileManager?.flushPendingDeferredSaves()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let privateDenItem = NSMenuItem(
            title: "Open Private Den",
            action: #selector(openPrivateDen),
            keyEquivalent: "")
        privateDenItem.target = self
        menu.addItem(privateDenItem)

        guard let profileManager else { return menu }

        menu.addItem(.separator())
        for profile in profileManager.profiles {
            let item = NSMenuItem(
                title: profile.name,
                action: #selector(openProfile(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.uuidString
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard
            let rawProfileID = sender.representedObject as? String,
            let profileID = UUID(uuidString: rawProfileID)
        else { return }
        _ = profileManager?.openWindow(for: profileID)
    }

    @objc private func openPrivateDen() {
        PrivateDenLauncher.open()
    }
}

@MainActor
private enum PrivateDenLauncher {
    static func open() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--private-den"]
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration)
    }
}
