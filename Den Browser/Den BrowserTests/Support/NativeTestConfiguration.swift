import AppKit
import DenDomain
import DenPresentationModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
func makeTestDefaults(suiteName: String = "DenBrowserTests-\(UUID().uuidString)") -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test defaults")
    }
    return defaults
}

@MainActor
final class TestWindow: NSWindow {
    private(set) var presentationRequests = 0
    private(set) var closeRequests = 0

    init() {
        super.init(
            contentRect: .init(x: 0, y: 0, width: 720, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        presentationRequests += 1
    }

    override func close() {
        closeRequests += 1
        super.close()
    }
}

@MainActor
func makeTestSheetNavigationManager(
    defaults: UserDefaults? = nil,
    scriptSource: String? = nil
) -> SheetNavigationManager {
    SheetNavigationManager(
        defaults: defaults ?? makeTestDefaults(),
        pasteboard: .withUniqueName(),
        scriptSource: scriptSource)
}

@MainActor
func makeTestBoardRuntimeConfiguration(
    defaults: UserDefaults? = nil,
    websiteDataStore: WKWebsiteDataStore = .nonPersistent(),
    sheetNavigation: SheetNavigationManager? = nil,
    preferences: AppPreferences? = nil,
    profileID: ProfileID? = nil,
    ipcSocketPath: String = DenSocketPath.resolve(),
    terminalCommandRunner: any TerminalCommandRunning = SubprocessCommandRunner(),
    requestWebExtensionContext: (() -> (WebExtensionHost, MV3WebExtensionWindow)?)? = nil
) -> BoardRuntimeConfiguration {
    let defaults = defaults ?? makeTestDefaults()
    let pasteboard = NSPasteboard.withUniqueName()
    return BoardRuntimeConfiguration(
        websiteDataStore: websiteDataStore,
        sheetNavigation: sheetNavigation
            ?? SheetNavigationManager(defaults: defaults, pasteboard: pasteboard, scriptSource: ""),
        preferences: preferences ?? AppPreferences(defaults: defaults),
        profileID: profileID, ipcSocketPath: ipcSocketPath, terminalCommandRunner: terminalCommandRunner,
        requestWebExtensionContext: requestWebExtensionContext)
}

@MainActor
func makeNativeTestState(desks: [DeskState]? = nil, boards: [BoardState] = []) -> DenState {
    let desks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    return DenState(desks: desks, focusedDeskID: desks.first?.id ?? DeskID())
}
