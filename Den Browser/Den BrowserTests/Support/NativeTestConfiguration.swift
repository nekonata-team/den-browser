import AppKit
import DenDomain
import DenModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    override init?(suiteName: String?) {
        super.init(suiteName: suiteName)
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            values[defaultName] = value
        } else {
            values.removeValue(forKey: defaultName)
        }
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func string(forKey defaultName: String) -> String? {
        lock.withLock { values[defaultName] as? String }
    }

    override func stringArray(forKey defaultName: String) -> [String]? {
        lock.withLock { values[defaultName] as? [String] }
    }

    override func data(forKey defaultName: String) -> Data? {
        lock.withLock { values[defaultName] as? Data }
    }

    override func bool(forKey defaultName: String) -> Bool {
        lock.withLock { values[defaultName] as? Bool ?? false }
    }

    override func integer(forKey defaultName: String) -> Int {
        lock.withLock { values[defaultName] as? Int ?? 0 }
    }

    override func double(forKey defaultName: String) -> Double {
        lock.withLock { values[defaultName] as? Double ?? 0 }
    }

    override func array(forKey defaultName: String) -> [Any]? {
        lock.withLock { values[defaultName] as? [Any] }
    }

    override func dictionary(forKey defaultName: String) -> [String: Any]? {
        lock.withLock { values[defaultName] as? [String: Any] }
    }

    override func removeObject(forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: defaultName)
    }

    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return values.isEmpty ? nil : values
    }

    override func removePersistentDomain(forName domainName: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }
}

@MainActor
func makeTestDefaults(suiteName: String = "DenBrowserTests-\(UUID().uuidString)") -> UserDefaults {
    guard let defaults = InMemoryUserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test defaults")
    }
    return defaults
}

func removeTestPreferencesPlist(suiteName: String) {
    let plistURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Preferences/\(suiteName).plist")
    try? FileManager.default.removeItem(at: plistURL)
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
            defer: false
        )
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
        scriptSource: scriptSource
    )
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
        profileID: profileID,
        ipcSocketPath: ipcSocketPath,
        terminalCommandRunner: terminalCommandRunner,
        requestWebExtensionContext: requestWebExtensionContext
    )
}

@MainActor
func makeNativeTestState(desks: [DeskState]? = nil, boards: [BoardState] = []) -> DenState {
    let desks = desks ?? [DeskState(label: "Desk", boards: boards, focusedBoardID: boards.first?.id)]
    return DenState(desks: desks, focusedDeskID: desks.first?.id ?? DeskID())
}
