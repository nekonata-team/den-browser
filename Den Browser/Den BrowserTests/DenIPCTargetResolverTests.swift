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
        let request = DenIPCRequest(command: .terminal(.kill(signal: "TERM")), boardID: nonExistentID)

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
        let request = DenIPCRequest(
            command: .sheet(.eval(DenSheetEvalPayload(script: "document.title"))),
            boardID: nonExistentID
        )

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

    @Test func multipleProfilesGenerateUniqueInitialDeskIDs() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)

        // Act
        let store1 = try #require(manager.store(for: manager.personalProfileID))
        let profile2 = try #require(manager.createProfile(name: "Work", color: .purple))
        let store2 = try #require(manager.store(for: profile2.id))

        // Assert
        let desk1ID = try #require(store1.state.desks.first?.id)
        let desk2ID = try #require(store2.state.desks.first?.id)
        #expect(desk1ID != desk2ID)
    }

    @Test func resolveTargetBoardWithDuplicateDeskIDsReturnsOwningStore() throws {
        // Arrange: Simulate legacy or imported persisted data where two profiles share identical Desk IDs
        let duplicateDeskID = UUID()
        let board1ID = UUID()
        let board2ID = UUID()

        let den1 = DenState(
            desks: [
                DeskState(
                    id: duplicateDeskID,
                    label: "Main 1",
                    boards: [
                        BoardState(
                            id: board1ID,
                            label: "Board 1",
                            width: 800,
                            currentSheetURL: URL(string: "https://p1.example.com")!
                        )
                    ]
                )
            ],
            focusedDeskID: duplicateDeskID
        )
        let den2 = DenState(
            desks: [
                DeskState(
                    id: duplicateDeskID,
                    label: "Main 2",
                    boards: [
                        BoardState(
                            id: board2ID,
                            label: "Board 2",
                            width: 800,
                            currentSheetURL: URL(string: "https://p2.example.com")!
                        )
                    ]
                )
            ],
            focusedDeskID: duplicateDeskID
        )

        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile1ID = UUID()
        let initialProfile = PersistedProfile(
            profile: ProfileState(id: profile1ID, name: "Profile 1", color: .blue, webProfileStore: .default),
            den: den1
        )
        let manager = makeProfileManager(directory: directory, initialProfile: initialProfile)
        let store1 = try #require(manager.store(for: profile1ID))

        let profile2 = try #require(manager.createProfile(name: "Profile 2", color: .green))
        let store2 = try #require(manager.store(for: profile2.id))
        store2.state = den2

        // Act: Target board1 without explicit profileID
        let request1 = DenIPCRequest(command: .sheet(.url), boardID: board1ID.uuidString)
        let result1 = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request1, in: manager)

        // Assert: Resolved store must be store1 (which owns board1), NEVER store2
        let (resolvedStore1, resolvedBoard1) = try #require(try? result1.get())
        #expect(resolvedBoard1.id == board1ID)
        #expect(resolvedStore1 === store1)
        #expect(resolvedStore1.board(for: board1ID) != nil)

        // Act: Target board2 without explicit profileID
        let request2 = DenIPCRequest(command: .sheet(.url), boardID: board2ID.uuidString)
        let result2 = DenIPCTargetResolver.resolveTargetWebBoardResult(request: request2, in: manager)

        // Assert: Resolved store must be store2 (which owns board2), NEVER store1
        let (resolvedStore2, resolvedBoard2) = try #require(try? result2.get())
        #expect(resolvedBoard2.id == board2ID)
        #expect(resolvedStore2 === store2)
        #expect(resolvedStore2.board(for: board2ID) != nil)
    }

    @Test func resolveTargetBoardReturnsSameStoreRegardlessOfProfileScoping() throws {
        // Arrange: Profile with two windows presenting different desks
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let profileID = manager.personalProfileID

        let window1ID = UUID()
        let window2ID = UUID()

        let storeWindow1 = try #require(
            manager.store(for: ProfileWindowRoute(windowID: window1ID, profileID: profileID)))
        let desk1ID = storeWindow1.presentedDeskID

        storeWindow1.createDesk(label: "Desk 2", preset: .empty)
        let desk2 = try #require(storeWindow1.state.desks.first(where: { $0.id != desk1ID }))
        let desk2ID = desk2.id
        storeWindow1.setFocusedDesk(desk1ID)

        let storeWindow2 = try #require(
            manager.store(for: ProfileWindowRoute(windowID: window2ID, profileID: profileID, deskID: desk2ID)))
        let board2ID = try #require(storeWindow2.createBoard(urlString: "https://window2.example.com/"))

        // Act 1: Resolve with explicit profileID
        let scopedRequest = DenIPCRequest(
            command: .sheet(.url),
            boardID: board2ID.uuidString,
            profileID: profileID.uuidString
        )
        let scopedResult = DenIPCTargetResolver.resolveTargetWebBoardResult(request: scopedRequest, in: manager)

        // Act 2: Resolve without profileID
        let unscopedRequest = DenIPCRequest(
            command: .sheet(.url),
            boardID: board2ID.uuidString
        )
        let unscopedResult = DenIPCTargetResolver.resolveTargetWebBoardResult(request: unscopedRequest, in: manager)

        // Assert: Both must return the exact same store (storeWindow2 presenting desk2)
        let (scopedStore, scopedBoard) = try #require(try? scopedResult.get())
        let (unscopedStore, unscopedBoard) = try #require(try? unscopedResult.get())

        #expect(scopedBoard.id == board2ID)
        #expect(unscopedBoard.id == board2ID)
        #expect(scopedStore === unscopedStore)
        #expect(scopedStore === storeWindow2)
        #expect(scopedStore.presentedDeskID == desk2ID)
    }

    @Test func resolveStoreAndDeskWithExplicitNonExistentDeskIDDoesNotFallback() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        _ = try #require(store.createBoard(urlString: "https://example.com/"))

        let nonExistentDeskID = UUID().uuidString

        // Act 1: Explicit non-existent deskID without profileID
        let request1 = DenIPCRequest(command: .desk(.list), deskID: nonExistentDeskID)
        let result1 = DenIPCTargetResolver.resolveStoreAndDesk(request: request1, in: manager)

        // Assert 1: Must fail, must NOT fall back to presented desk
        switch result1 {
        case .failure(let error):
            #expect(error == .noActiveDesk)
        case .success:
            Issue.record("Expected failure on non-existent desk ID")
        }

        // Act 2: Explicit non-existent deskID with profileID
        let request2 = DenIPCRequest(
            command: .desk(.list),
            deskID: nonExistentDeskID,
            profileID: manager.personalProfileID.uuidString
        )
        let result2 = DenIPCTargetResolver.resolveStoreAndDesk(request: request2, in: manager)

        // Assert 2: Must fail, must NOT fall back to presented desk
        switch result2 {
        case .failure(let error):
            #expect(error == .noActiveDesk)
        case .success:
            Issue.record("Expected failure on non-existent desk ID")
        }
    }

    private func temporaryProfileDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-resolver-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeProfileManager(
        directory: URL,
        initialProfile: PersistedProfile? = nil
    ) -> ProfileManager {
        let suiteName = "IPCTargetResolverPreferences-\(UUID().uuidString)"
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: suiteName) ?? .standard)
        let navigation = SheetNavigationManager(
            defaults: UserDefaults(suiteName: suiteName) ?? .standard,
            scriptSource: "")
        return ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: preferences,
            removeDataStore: { _ in },
            initialProfile: initialProfile)
    }
}
