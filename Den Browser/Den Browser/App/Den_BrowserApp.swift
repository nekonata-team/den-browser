import AppKit
import DenApplication
import DenDomain
import DenInfrastructure
import DenPresentationModels
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
                registerKeyboardWindow: { window, windowModel in
                    keyboardController.register(windowModel: windowModel, for: window)
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
                windowID: profileManager.personalProfileID.rawValue,
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

    @FocusedValue(\.denWindowModel) private var windowModel
    @FocusedValue(\.denController) private var controller
    @FocusedValue(\.profileID) private var profileID
    @FocusedValue(\.profileWindowID) private var profileWindowID
    @Environment(\.openWindow) private var openWindow

    private func perform(_ action: AppAction) {
        AppActionHandler.perform(action, controller: controller, windowModel: windowModel)
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updaterController.checkForUpdates()
            }
        }

        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .saveItem) {
            if controller == nil {
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
                    controller == nil
                        || windowModel?.pendingConfirmation != nil
                        || windowModel?.isFullscreenActive == true)
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
                .disabled(controller == nil)
            Button("Commands…") { perform(.application(.showUniversalSearch(commandsOnly: true))) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(controller == nil)

            Button("Toggle Den Mode") { perform(.application(.toggleDenMode)) }
                .disabled(controller == nil)

            Menu("Board") {
                Button("Open Board") { perform(.board(.showOpenPanel)) }
                    .keyboardShortcut("t", modifiers: [.command])
                    .disabled(controller == nil)
                Button("Inspect Current Sheet") {
                    guard let board = controller?.focusedBoard, board.isWeb else { return }
                    controller?.createInspectionBoard(targetBoardID: board.id)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(controller?.focusedBoard?.isWeb != true)
                Button("Create Terminal Side Board") { perform(.board(.createTerminalSideBoard)) }
                    .keyboardShortcut("d", modifiers: [.command])
                    .disabled(controller?.focusedBoard?.isTerminal != true)
                Menu("Sheet Size") {
                    Button(
                        controller?.focusedBoard?.isTerminal == true
                            ? "Increase Font Size" : "Increase Sheet Scale"
                    ) {
                        perform(.board(.increaseSheetSize))
                    }
                    .keyboardShortcut("=", modifiers: [.command, .shift])

                    Button(
                        controller?.focusedBoard?.isTerminal == true
                            ? "Decrease Font Size" : "Decrease Sheet Scale"
                    ) {
                        perform(.board(.decreaseSheetSize))
                    }
                    .keyboardShortcut("-", modifiers: [.command])

                    Button(
                        controller?.focusedBoard?.isTerminal == true
                            ? "Reset Font Size" : "Reset Sheet Scale"
                    ) {
                        perform(.board(.resetSheetSize))
                    }
                    .keyboardShortcut("0", modifiers: [.command])
                }
                .disabled(!(controller?.focusedBoard?.isWeb == true || controller?.focusedBoard?.isTerminal == true))
                Button("Edit Focused Board Link") {
                    perform(.board(.showEditLinkPanel))
                }
                .keyboardShortcut("l", modifiers: [.command])
                .disabled(controller?.focusedBoard?.isWeb != true)

                Divider()

                Button("Reload Current Sheet") { perform(.board(.reload)) }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(controller?.focusedBoard?.isWeb != true)
                Button("Hard Reload Current Sheet") {
                    perform(.board(.reloadFromOrigin))
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(controller?.focusedBoard?.isWeb != true)
                Button("Capture Current Sheet Screenshot…") {
                    perform(.board(.captureSheet))
                }
                .disabled(controller?.focusedBoard?.isWeb != true && controller?.focusedBoard?.isTerminal != true)

                Divider()

                Button("Remove Board") { perform(.board(.remove)) }
                    .keyboardShortcut("w", modifiers: [.command])
                    .disabled(
                        controller?.focusedDesk?.focusedBoardID == nil
                            || windowModel?.pendingConfirmation != nil)
                Button("Restore Removed Board") { perform(.board(.restore)) }
                    .disabled(controller?.recentlyRemovedBoards.isEmpty ?? true)
            }

            Button("zmx Sessions…") { windowModel?.showZmxSessions() }
                .disabled(controller?.zmxClient.isConfigured != true)

            Menu("Drawer") {
                Button("Restore Discarded Drawer Item") {
                    perform(.drawer(.restoreDiscardedItem))
                }
                .disabled(controller?.recentlyDiscardedDrawerItems.isEmpty ?? true)
            }

            Menu("Desk") {
                Button("New Desk") { perform(.desk(.showNewPanel)) }
                    .disabled(controller?.canCreateDesk != true)
                Button("Save Desk as Preset…") { perform(.desk(.showSavePresetPanel)) }
                    .disabled(controller?.focusedDesk?.boards.isEmpty != false)

                Menu("Export") {
                    Button("Save Desk Links as Markdown…") {
                        controller?.exportFocusedDeskLinks()
                    }
                    .disabled(controller?.canExportFocusedDeskLinks != true)

                    Button("Copy Desk Links as Markdown") {
                        controller?.copyFocusedDeskLinks()
                    }
                    .disabled(controller?.canExportFocusedDeskLinks != true)
                }
                .disabled(controller == nil)

                Menu("Resize Boards to Fit") {
                    ForEach(1...9, id: \.self) { count in
                        Button(count == 1 ? "1 Board" : "\(count) Boards") {
                            perform(.desk(.resizeBoards(count)))
                        }
                        .disabled(windowModel?.canResizeFocusedDeskBoards(toFit: count) != true)
                    }
                }
                .disabled(controller == nil)

                Button("Reload Focused Desk Sheets") {
                    perform(.desk(.reloadSheets))
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(controller?.focusedDesk?.boards.contains(where: \.isWeb) != true)

                Divider()

                Button("Delete Desk") { perform(.desk(.delete)) }
                    .disabled(controller?.canDeleteFocusedDesk != true)
            }

            Menu("Presentation") {
                Button("Toggle Overview") { windowModel?.toggleOverview() }
                    .disabled(controller == nil)
                Button("Toggle Zen View") { perform(.application(.toggleZenView)) }
                    .disabled(controller == nil)
                Toggle(
                    "Focus Mode",
                    isOn: Binding(
                        get: { windowModel?.isFocusModePresented == true },
                        set: { isPresented in
                            guard isPresented != (windowModel?.isFocusModePresented ?? false) else { return }
                            perform(.application(.toggleFocusMode))
                        })
                )
                .disabled(controller == nil || windowModel?.temporaryContext != nil)
                Button("Toggle Drawer") { perform(.drawer(.toggle)) }
                    .disabled(controller == nil)
            }

            Button("Keyboard Shortcuts…") { perform(.application(.showKeyboardShortcuts)) }
                .disabled(controller == nil)
            Button("Settings…") {
                AppActionHandler.perform(
                    .application(.openSettings),
                    controller: controller,
                    windowModel: windowModel,
                    openSettings: { openSettingsCoordinator.open() })
            }
            .keyboardShortcut(",", modifiers: [])
            .disabled(windowModel?.isDenMode != true || windowModel?.temporaryContext != nil)

            Divider()
            Button("Reset Den") { windowModel?.requestResetDenConfirmation() }
                .disabled(controller == nil || windowModel?.pendingConfirmation != nil)
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
