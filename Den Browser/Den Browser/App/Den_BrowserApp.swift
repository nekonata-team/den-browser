import AppKit
import DenApplication
import DenDomain
import DenInfrastructure
import DenModels
import Sparkle
import SwiftUI

@main
struct Den_BrowserApp: App {
    @NSApplicationDelegateAdaptor(DenApplicationDelegate.self) private var appDelegate
    private let updaterController = UpdaterControllerCoordinator()
    @State private var preferences: AppPreferences
    @State private var sheetNavigationSettingsModel: SheetNavigationSettingsModel
    @State private var profileSettingsModel: ProfileSettingsModel
    @State private var inputMethodSettingsModel: InputMethodSettingsModel
    @State private var terminalSettingsModel: TerminalSettingsModel
    @State private var essentialsSettingsModel: EssentialsSettingsModel
    @State private var appearanceModel: AppearanceModel
    @State private var shortcutSettingsModel: ShortcutSettingsModel
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
        _inputMethodSettingsModel = State(
            initialValue: InputMethodSettingsModel(
                read: { preferences.rememberBoardInputMethod }, write: { preferences.setRememberBoardInputMethod($0) }))
        _terminalSettingsModel = State(initialValue: TerminalSettingsModel(preferences: preferences))
        _essentialsSettingsModel = State(
            initialValue: EssentialsSettingsModel(
                read: { preferences.essentials }, persist: { preferences.setEssentials($0) }))
        _appearanceModel = State(initialValue: AppearanceModel(preferences: preferences))
        _shortcutSettingsModel = State(initialValue: ShortcutSettingsModel(preferences: preferences))
        _sheetNavigation = State(initialValue: sheetNavigation)
        _sheetNavigationSettingsModel = State(initialValue: SheetNavigationSettingsModel(manager: sheetNavigation))
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
        _profileSettingsModel = State(initialValue: ProfileSettingsModel(manager: manager))
        appDelegate.profileManager = manager
        PerformanceTrace.mark("ProfileManager initialized", category: "Launch")
        DenIPCService.shared.start(profileManager: manager)
    }

    var body: some Scene {
        WindowGroup(
            "Den Browser",
            id: profileManager.isPrivateDen ? "private-den-window" : "profile-window",
            for: ProfileWindowRoute.self
        ) { $route in
            ProfileWindowView(
                route: route,
                startUpdater: { updaterController.start() },
                registerKeyboardWindow: { window, windowModel in
                    keyboardController.register(windowModel: windowModel, for: window)
                },
                unregisterKeyboardWindow: { window in
                    keyboardController.unregister(window: window)
                }
            )
            .environment(profileManager)
            .environment(preferences)
            .environment(appearanceModel)
            .environment(shortcutSettingsModel)
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
                windowID: profileManager.personalProfileID.rawValue,
                profileID: profileManager.personalProfileID)
        }
        .restorationBehavior(profileManager.isPrivateDen ? .disabled : .automatic)
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
                .environment(appearanceModel)
                .environment(essentialsSettingsModel)
                .environment(terminalSettingsModel)
                .environment(profileSettingsModel)
                .environment(inputMethodSettingsModel)
                .environment(sheetNavigationSettingsModel)
                .environment(shortcutSettingsModel)
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

    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.denWindowModel) private var windowModel
    @FocusedValue(\.profileWindowSession) private var session
    @FocusedValue(\.profileID) private var profileID
    @FocusedValue(\.profileWindowID) private var profileWindowID

    private func perform(_ action: AppAction) {
        AppActionHandler.perform(action, session: session, windowModel: windowModel)
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updaterController.checkForUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .saveItem) {
            if session == nil {
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command])
            } else {
                Button("Close Profile Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(windowModel?.pendingConfirmation != nil)
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Board Activity") { perform(.overview(.toggleActivity)) }
                .keyboardShortcut(.escape, modifiers: [.shift])
                .disabled(
                    session == nil
                        || windowModel?.pendingConfirmation != nil
                        || windowModel?.isFullscreenActive == true)
        }

        CommandMenu("Profile") {
            ForEach(profileManager.profiles) { profile in
                Button(profile.name) {
                    guard profileManager.canOpenWindow(for: profile.id) else { return }
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
                    windowModel?.setTemporaryContext(.profilePicker)
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
            Button("Universal Search…") { perform(.application(.showUniversalSearch(commandsOnly: false))) }
                .keyboardShortcut("p", modifiers: [.command])
                .disabled(session == nil)
            Button("Commands…") { perform(.application(.showUniversalSearch(commandsOnly: true))) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(session == nil)

            Button("Toggle Den Mode") { perform(.application(.toggleDenMode)) }
                .disabled(session == nil)

            Menu("Board") {
                Button("Open Board") { perform(.board(.showOpenPanel)) }
                    .keyboardShortcut("t", modifiers: [.command])
                    .disabled(session == nil)
                Button("Inspect Current Sheet") {
                    guard let board = windowModel?.focusedBoard, board.isWeb else { return }
                    session?.sideBoards.createInspectionBoard(targetBoardID: board.id)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(windowModel?.focusedBoard?.isWeb != true)
                Button("Create Terminal Side Board") { perform(.board(.createTerminalSideBoard)) }
                    .keyboardShortcut("d", modifiers: [.command])
                    .disabled(windowModel?.focusedBoard?.isTerminal != true)
                Menu("Sheet Size") {
                    Button(
                        windowModel?.focusedBoard?.isTerminal == true
                            ? "Increase Font Size" : "Increase Sheet Scale"
                    ) {
                        perform(.board(.increaseSheetSize))
                    }
                    .keyboardShortcut("=", modifiers: [.command, .shift])

                    Button(
                        windowModel?.focusedBoard?.isTerminal == true
                            ? "Decrease Font Size" : "Decrease Sheet Scale"
                    ) {
                        perform(.board(.decreaseSheetSize))
                    }
                    .keyboardShortcut("-", modifiers: [.command])

                    Button(
                        windowModel?.focusedBoard?.isTerminal == true
                            ? "Reset Font Size" : "Reset Sheet Scale"
                    ) {
                        perform(.board(.resetSheetSize))
                    }
                    .keyboardShortcut("0", modifiers: [.command])
                }
                .disabled(!(windowModel?.focusedBoard?.isWeb == true || windowModel?.focusedBoard?.isTerminal == true))
                Button("Edit Focused Board Link") {
                    perform(.board(.showEditLinkPanel))
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(windowModel?.focusedBoard?.isWeb != true)

                Divider()

                Button("Reload Current Sheet") { perform(.board(.reload)) }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(windowModel?.focusedBoard?.isWeb != true)
                Button("Hard Reload Current Sheet") {
                    perform(.board(.reloadFromOrigin))
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(windowModel?.focusedBoard?.isWeb != true)
                Button("Capture Current Sheet Screenshot…") {
                    perform(.board(.captureSheet))
                }
                .disabled(windowModel?.focusedBoard?.isWeb != true && windowModel?.focusedBoard?.isTerminal != true)

                Divider()

                Button("Remove Board") { perform(.board(.remove)) }
                    .keyboardShortcut("w", modifiers: [.command])
                    .disabled(
                        windowModel?.focusedDesk?.focusedBoardID == nil
                            || windowModel?.pendingConfirmation != nil)
                Button("Restore Removed Board") { perform(.board(.restore)) }
                    .disabled(session?.resources.data.snapshot.recentlyRemovedBoards.isEmpty ?? true)
            }

            Button("zmx Sessions…") { windowModel?.showZmxSessions() }
                .disabled(session?.context.zmxClient.isConfigured != true)

            Menu("Drawer") {
                Button("Restore Discarded Drawer Item") {
                    perform(.drawer(.restoreDiscardedItem))
                }
                .disabled(session?.resources.data.snapshot.recentlyDiscardedDrawerItems.isEmpty ?? true)
            }

            Menu("Desk") {
                Button("New Desk") { perform(.desk(.showNewPanel)) }
                    .disabled(windowModel?.desks.canCreateDesk != true)
                Button("Save Desk as Preset…") { perform(.desk(.showSavePresetPanel)) }
                    .disabled(windowModel?.focusedDesk == nil)

                Menu("Export") {
                    Button("Save Desk Links as Markdown…") {
                        session?.deskLinks.exportFocusedDeskLinks()
                    }
                    .disabled(windowModel?.desks.canExportFocusedDeskLinks != true)

                    Button("Copy Desk Links as Markdown") {
                        session?.deskLinks.copyFocusedDeskLinks()
                    }
                    .disabled(windowModel?.desks.canExportFocusedDeskLinks != true)
                }
                .disabled(session == nil)

                Menu("Resize Boards to Fit") {
                    ForEach(1...9, id: \.self) { count in
                        Button(count == 1 ? "1 Board" : "\(count) Boards") {
                            perform(.desk(.resizeBoards(count)))
                        }
                        .disabled(windowModel?.canResizeFocusedDeskBoards(toFit: count) != true)
                    }
                }
                .disabled(session == nil)

                Button("Reload Focused Desk Sheets") {
                    perform(.desk(.reloadSheets))
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(windowModel?.focusedDesk?.boards.contains(where: \.isWeb) != true)

                Divider()

                Button("Delete Desk") { perform(.desk(.delete)) }
                    .disabled(windowModel?.desks.canDeleteFocusedDesk != true)
            }

            Menu("Presentation") {
                Button("Toggle Overview") { windowModel?.toggleOverview() }
                    .disabled(session == nil)
                Button("Toggle Zen View") { perform(.application(.toggleZenView)) }
                    .disabled(session == nil)
                Toggle(
                    "Focus Mode",
                    isOn: Binding(
                        get: { windowModel?.isFocusModePresented == true },
                        set: { isPresented in
                            guard isPresented != (windowModel?.isFocusModePresented ?? false) else { return }
                            perform(.application(.toggleFocusMode))
                        })
                )
                .disabled(session == nil || windowModel?.temporaryContext != nil)
                Button("Toggle Drawer") { perform(.drawer(.toggle)) }
                    .disabled(session == nil)
            }

            Button("Keyboard Shortcuts…") { perform(.application(.showKeyboardShortcuts)) }
                .disabled(session == nil)
            Button("Settings…") {
                AppActionHandler.perform(
                    .application(.openSettings),
                    session: session,
                    windowModel: windowModel,
                    openSettings: { openSettingsCoordinator.open() })
            }
            .keyboardShortcut(",", modifiers: [])
            .disabled(windowModel?.isDenMode != true || windowModel?.temporaryContext != nil)

            Divider()
            Button("Reset Den") { windowModel?.requestResetDenConfirmation() }
                .disabled(session == nil || windowModel?.pendingConfirmation != nil)
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
            item.representedObject = profile.id.rawValue.uuidString
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openProfile(_ sender: NSMenuItem) {
        guard
            let rawProfileID = sender.representedObject as? String,
            let profileID = UUID(uuidString: rawProfileID).map(ProfileID.init)
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
