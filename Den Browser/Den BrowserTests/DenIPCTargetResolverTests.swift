import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenIPCTargetResolverTests {

    @Test func resolveTargetTerminalBoardFindsExplicitBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let terminalBoardID = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))
        let explicitRequest = DenIPCRequest(command: "terminal.text", boardID: terminalBoardID.uuidString)

        // Act
        let resolved = DenIPCTargetResolver.resolveTargetTerminalBoard(request: explicitRequest, in: manager)

        // Assert
        let target = try #require(resolved)
        #expect(target.1.id == terminalBoardID)
    }

    @Test func resolveTargetTerminalBoardFindsAmbientBoardRelativeToCallerWebBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let terminalBoardID = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))
        let webBoardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let ambientRequest = DenIPCRequest(command: "terminal.text", callerBoardID: webBoardID.uuidString)

        // Act
        let resolved = DenIPCTargetResolver.resolveTargetTerminalBoard(request: ambientRequest, in: manager)

        // Assert
        let target = try #require(resolved)
        #expect(target.1.id == terminalBoardID)
    }

    @Test func resolveTargetTerminalBoardFindsAmbientBoardWhenCallerIsTerminalBoardItself() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let terminalBoardID = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))
        let selfRequest = DenIPCRequest(command: "terminal.text", callerBoardID: terminalBoardID.uuidString)

        // Act
        let resolved = DenIPCTargetResolver.resolveTargetTerminalBoard(request: selfRequest, in: manager)

        // Assert
        let target = try #require(resolved)
        #expect(target.1.id == terminalBoardID)
    }

    private func temporaryProfileDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-resolver-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeProfileManager(directory: URL) -> ProfileManager {
        let suiteName = "IPCTargetResolverPreferences-\(UUID().uuidString)"
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        let navigation = SheetNavigationManager(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard,
            scriptSource: "")
        return ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: preferences,
            removeDataStore: { _ in })
    }
}
