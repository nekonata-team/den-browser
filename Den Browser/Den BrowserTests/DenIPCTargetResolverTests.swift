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

    @Test func resolveTargetTerminalBoardReturnsNilForUnknownExplicitBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        _ = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))

        let nonExistentID = UUID().uuidString
        let request = DenIPCRequest(command: "terminal.kill", boardID: nonExistentID)

        // Act
        let resolved = DenIPCTargetResolver.resolveTargetTerminalBoard(request: request, in: manager)

        // Assert: MUST NOT fall back to the active terminal board
        #expect(resolved == nil)
    }

    @Test func resolveTargetWebBoardReturnsNilForUnknownExplicitBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        _ = try #require(store.createBoard(urlString: "https://example.com/"))

        let nonExistentID = UUID().uuidString
        let request = DenIPCRequest(command: "sheet.eval", boardID: nonExistentID)

        // Act
        let resolved = DenIPCTargetResolver.resolveTargetWebBoard(request: request, in: manager)

        // Assert: MUST NOT fall back to the active web board
        #expect(resolved == nil)
    }

    @Test func resolveTargetWebBoardReturnsNilWhenCallerDeskHasNoWebBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))

        // Desk 1 has a web board
        _ = try #require(store.createBoard(urlString: "https://example.com/"))

        // Create Desk 2 with only a terminal board
        store.createDesk(label: "Terminal Only", preset: .empty)
        guard let desk2 = store.state.desks.last else {
            Issue.record("Desk 2 missing")
            return
        }
        _ = store.setFocusedDesk(desk2.id)
        let terminalBoardID = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))

        let ambientRequest = DenIPCRequest(command: "sheet.url", callerBoardID: terminalBoardID.uuidString)

        // Act
        let resolved = DenIPCTargetResolver.resolveTargetWebBoard(request: ambientRequest, in: manager)

        // Assert: MUST NOT fall back to Desk 1's web board
        #expect(resolved == nil)
    }

    @Test func boardCloseReturnsErrorAndDoesNotCloseActiveBoardOnInvalidID() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        let request = DenIPCRequest(command: "board.close", args: ["not-a-valid-uuid"])

        // Act
        let response = await service.handleRequest(request)

        // Assert: Must return failure and active board must still exist
        #expect(response.isOk == false)
        #expect(response.error?.contains("Invalid board ID") == true)
        #expect(store.board(for: boardID) != nil)
    }

    @Test func boardCloseReturnsErrorAndDoesNotCloseActiveBoardOnNonExistentUUID() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        let nonExistentID = UUID().uuidString
        let request = DenIPCRequest(command: "board.close", args: [nonExistentID])

        // Act
        let response = await service.handleRequest(request)

        // Assert: Must return failure and active board must still exist
        #expect(response.isOk == false)
        #expect(response.error?.contains("Board not found") == true)
        #expect(store.board(for: boardID) != nil)
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
