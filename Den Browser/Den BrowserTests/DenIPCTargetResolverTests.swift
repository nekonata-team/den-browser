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
        let explicitRequest = DenIPCRequest(
            command: .terminal(.text),
            boardID: terminalBoardID.uuidString)

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
        let ambientRequest = DenIPCRequest(
            command: .terminal(.text),
            callerBoardID: webBoardID.uuidString)

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
        let selfRequest = DenIPCRequest(
            command: .terminal(.text),
            callerBoardID: terminalBoardID.uuidString)

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
        let request = DenIPCRequest(command: .terminal(.kill), boardID: nonExistentID)

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
        let request = DenIPCRequest(command: .sheet(.eval), boardID: nonExistentID)

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

        let ambientRequest = DenIPCRequest(command: .sheet(.url), callerBoardID: terminalBoardID.uuidString)

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

        let request = DenIPCRequest(command: .board(.close), boardID: "not-a-valid-uuid")

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
        let request = DenIPCRequest(command: .board(.close), boardID: nonExistentID)

        // Act
        let response = await service.handleRequest(request)

        // Assert: Must return failure and active board must still exist
        #expect(response.isOk == false)
        #expect(response.error?.contains("Board not found") == true)
        #expect(store.board(for: boardID) != nil)
    }

    @Test func boardCloseRejectsPositionalBoardID() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        let request = DenIPCRequest(command: .board(.close), args: [boardID.uuidString])

        // Act
        let response = await service.handleRequest(request)

        // Assert: The deprecated positional form must not fall back to the ambient target.
        #expect(response.isOk == false)
        #expect(response.error?.contains("Usage: den board close [--board <id>]") == true)
        #expect(store.board(for: boardID) != nil)
    }

    @Test func resolveTargetWebBoardWithExplicitProfileFindsBoardInThatProfile() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store1 = try #require(manager.store(for: manager.personalProfileID))
        _ = try #require(store1.createBoard(urlString: "https://profile1.example.com/"))

        let profile2 = try #require(manager.createProfile(name: "Work", color: .purple))
        let store2 = try #require(manager.store(for: profile2.id))
        let board2ID = try #require(store2.createBoard(urlString: "https://profile2.example.com/"))

        let request = DenIPCRequest(
            command: .sheet(.url),
            profileID: profile2.id.uuidString
        )

        // Act
        let result = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: manager)

        // Assert
        let (resolvedStore, resolvedBoard) = try #require(try? result.get())
        #expect(resolvedBoard.id == board2ID)
        #expect(resolvedStore === store2)
    }

    @Test func resolveTargetWebBoardFailsOnInvalidProfileUUID() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        _ = try #require(manager.store(for: manager.personalProfileID))

        let request = DenIPCRequest(
            command: .sheet(.url),
            profileID: "not-a-valid-uuid"
        )

        // Act
        let result = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: manager)

        // Assert
        switch result {
        case .failure(let error):
            #expect(error == .invalidProfileID("not-a-valid-uuid"))
        case .success:
            Issue.record("Expected failure on invalid profile UUID")
        }
    }

    @Test func resolveTargetWebBoardFailsOnUnknownProfileUUID() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        _ = try #require(manager.store(for: manager.personalProfileID))

        let unknownUUID = UUID().uuidString
        let request = DenIPCRequest(
            command: .sheet(.url),
            profileID: unknownUUID
        )

        // Act
        let result = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: manager)

        // Assert
        switch result {
        case .failure(let error):
            #expect(error == .profileNotFound(unknownUUID))
        case .success:
            Issue.record("Expected failure on unknown profile UUID")
        }
    }

    @Test func resolveTargetWebBoardFailsWhenProfileHasNoActiveWindow() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        _ = try #require(manager.store(for: manager.personalProfileID))

        let profileWithoutWindow = try #require(manager.createProfile(name: "No Window", color: .gray))
        let request = DenIPCRequest(
            command: .sheet(.url),
            profileID: profileWithoutWindow.id.uuidString
        )

        // Act
        let result = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: manager)

        // Assert
        switch result {
        case .failure(let error):
            #expect(error == .profileHasNoActiveWindow(profileWithoutWindow.id.uuidString))
        case .success:
            Issue.record("Expected failure when profile has no active window")
        }
    }

    @Test func resolveTargetWebBoardRejectsBoardNotInSpecifiedProfile() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store1 = try #require(manager.store(for: manager.personalProfileID))
        let board1ID = try #require(store1.createBoard(urlString: "https://profile1.example.com/"))

        let profile2 = try #require(manager.createProfile(name: "Work", color: .purple))
        _ = try #require(manager.store(for: profile2.id))

        let request = DenIPCRequest(
            command: .sheet(.url),
            boardID: board1ID.uuidString,
            profileID: profile2.id.uuidString
        )

        // Act
        let result = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: manager)

        // Assert
        switch result {
        case .failure(let error):
            #expect(error == .boardNotFound(board1ID.uuidString))
        case .success:
            Issue.record("Expected failure when board is not in specified profile")
        }
    }

    @Test func resolveTargetWebBoardWithExplicitProfileAndCallerBoardResolvesAdjacentBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profile2 = try #require(manager.createProfile(name: "Work", color: .purple))
        let store2 = try #require(manager.store(for: profile2.id))
        let terminalBoardID = try #require(store2.createTerminalBoard(workingDirectory: "/tmp", focus: true))
        let webBoardID = try #require(store2.createBoard(urlString: "https://profile2.example.com/"))

        let request = DenIPCRequest(
            command: .sheet(.url),
            callerBoardID: terminalBoardID.uuidString,
            profileID: profile2.id.uuidString
        )

        // Act
        let result = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request, in: manager)

        // Assert
        let (resolvedStore, resolvedBoard) = try #require(try? result.get())
        #expect(resolvedBoard.id == webBoardID)
        #expect(resolvedStore === store2)
    }

    @Test func boardCloseWithProfileIDClosesBoardInTargetProfile() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store1 = try #require(manager.store(for: manager.personalProfileID))
        let board1ID = try #require(store1.createBoard(urlString: "https://profile1.example.com/"))

        let profile2 = try #require(manager.createProfile(name: "Work", color: .purple))
        let store2 = try #require(manager.store(for: profile2.id))
        let board2ID = try #require(store2.createBoard(urlString: "https://profile2.example.com/"))

        let service = DenIPCService(profileManager: manager)

        // Act: Close board2 with profile2
        let request = DenIPCRequest(
            command: .board(.close),
            boardID: board2ID.uuidString,
            profileID: profile2.id.uuidString
        )
        let response = await service.handleRequest(request)

        // Assert
        #expect(response.isOk == true)
        #expect(store2.board(for: board2ID) == nil)
        #expect(store1.board(for: board1ID) != nil)
    }

    @Test func boardCloseWithProfileIDRejectsBoardInDifferentProfile() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store1 = try #require(manager.store(for: manager.personalProfileID))
        let board1ID = try #require(store1.createBoard(urlString: "https://profile1.example.com/"))

        let profile2 = try #require(manager.createProfile(name: "Work", color: .purple))
        let store2 = try #require(manager.store(for: profile2.id))
        let board2ID = try #require(store2.createBoard(urlString: "https://profile2.example.com/"))

        let service = DenIPCService(profileManager: manager)

        // Act: Attempt to close board1 scoping to profile2
        let request = DenIPCRequest(
            command: .board(.close),
            boardID: board1ID.uuidString,
            profileID: profile2.id.uuidString
        )
        let response = await service.handleRequest(request)

        // Assert
        #expect(response.isOk == false)
        #expect(response.error?.contains("Board not found: \(board1ID.uuidString)") == true)
        #expect(store1.board(for: board1ID) != nil)
        #expect(store2.board(for: board2ID) != nil)
    }

    @Test func boardCloseClosesTerminalBoardWhenBoardIDSpecified() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let terminalBoardID = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))
        let service = DenIPCService(profileManager: manager)

        let request = DenIPCRequest(
            command: .board(.close),
            boardID: terminalBoardID.uuidString
        )
        let response = await service.handleRequest(request)

        // Assert
        #expect(response.isOk == true)
        #expect(store.board(for: terminalBoardID) == nil)
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
