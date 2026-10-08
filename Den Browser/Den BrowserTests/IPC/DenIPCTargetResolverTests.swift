import DenDomain
import DenIPCProtocol
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
        // Act
        let resolved = try DenIPCTargetResolver.resolveBoard(
            target: .explicit(terminalBoardID.rawValue), context: DenIPCCallerContext(), kind: .terminal, in: manager
        ).get()

        // Assert
        #expect(resolved.board.id == terminalBoardID)
    }

    @Test func ambientBoardTargetSkipsFocusedInspectionBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let webBoardID = try #require(store.createBoard(urlString: "https://example.com/"))
        _ = try #require(store.createInspectionBoard(targetBoardID: webBoardID))
        // Act
        let resolved = try DenIPCTargetResolver.resolveBoard(
            target: .automatic, context: DenIPCCallerContext(), kind: .any, in: manager
        ).get()

        // Assert
        #expect(resolved.board.id == webBoardID)
        #expect(resolved.board.isWeb)
    }

    @Test func explicitAnyBoardTargetFindsInspectionBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let webBoardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let inspectionBoardID = try #require(store.createInspectionBoard(targetBoardID: webBoardID))
        // Act
        let resolved = try DenIPCTargetResolver.resolveBoard(
            target: .explicit(inspectionBoardID.rawValue), context: DenIPCCallerContext(), kind: .any, in: manager
        ).get()

        // Assert
        #expect(resolved.board.id == inspectionBoardID)
        #expect(resolved.board.isInspection)
    }

    @Test func readInspectionResolvesOnlyTheExplicitInspectionBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let webBoardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let inspectionBoardID = try #require(store.createInspectionBoard(targetBoardID: webBoardID))
        // Act
        let resolved = try DenIPCTargetResolver.resolveBoard(
            target: .explicit(inspectionBoardID.rawValue), context: DenIPCCallerContext(), kind: .inspection,
            in: manager
        ).get()

        // Assert
        #expect(resolved.board.id == inspectionBoardID)
        #expect(resolved.board.isInspection)
    }

    @Test func resolveTargetTerminalBoardFindsAmbientBoardRelativeToCallerWebBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let terminalBoardID = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))
        let webBoardID = try #require(store.createBoard(urlString: "https://example.com/"))
        // Act
        let resolved = try DenIPCTargetResolver.resolveBoard(
            target: .automatic,
            context: DenIPCCallerContext(callerBoardID: webBoardID.rawValue),
            kind: .terminal,
            in: manager
        ).get()

        // Assert
        #expect(resolved.board.id == terminalBoardID)
    }

    @Test func resolveTargetTerminalBoardFindsAmbientBoardWhenCallerIsTerminalBoardItself() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let terminalBoardID = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))
        // Act
        let resolved = try DenIPCTargetResolver.resolveBoard(
            target: .automatic,
            context: DenIPCCallerContext(callerBoardID: terminalBoardID.rawValue),
            kind: .terminal,
            in: manager
        ).get()

        // Assert
        #expect(resolved.board.id == terminalBoardID)
    }

    @Test func resolveTargetTerminalBoardFailsForUnknownExplicitBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        _ = try #require(store.createTerminalBoard(workingDirectory: "/tmp", focus: true))

        let nonExistentID = UUID()

        // Act
        let resolved = DenIPCTargetResolver.resolveBoard(
            target: .explicit(nonExistentID), context: DenIPCCallerContext(), kind: .terminal, in: manager
        )

        // Assert: MUST NOT fall back to the active terminal board
        if case .failure(let error) = resolved {
            #expect(error == .boardNotFound(nonExistentID.uuidString))
        } else {
            Issue.record("Expected failure for an unknown explicit Terminal Board")
        }
    }

    @Test func resolveTargetWebBoardFailsForUnknownExplicitBoard() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        _ = try #require(store.createBoard(urlString: "https://example.com/"))

        let nonExistentID = UUID()

        // Act
        let resolved = DenIPCTargetResolver.resolveBoard(
            target: .explicit(nonExistentID), context: DenIPCCallerContext(), kind: .web, in: manager
        )

        // Assert: MUST NOT fall back to the active web board
        if case .failure(let error) = resolved {
            #expect(error == .boardNotFound(nonExistentID.uuidString))
        } else {
            Issue.record("Expected failure for an unknown explicit Web Board")
        }
    }

    @Test func resolveTargetWebBoardFailsWhenCallerDeskHasNoWebBoard() throws {
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

        // Act
        let resolved = DenIPCTargetResolver.resolveBoard(
            target: .automatic,
            context: DenIPCCallerContext(callerBoardID: terminalBoardID.rawValue),
            kind: .web,
            in: manager
        )

        // Assert: MUST NOT fall back to Desk 1's web board
        if case .failure(let error) = resolved {
            #expect(error == .noTargetBoard("Web"))
        } else {
            Issue.record("Expected failure when the caller Desk has no Web Board")
        }
    }

    @Test func boardCloseReturnsErrorAndDoesNotCloseActiveBoardOnNonExistentUUID() async throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        let nonExistentID = UUID()
        let request = DenIPCRequest(operation: .boardClose(target: .explicit(nonExistentID)))

        // Act
        let response = await service.handleRequest(request).result

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

        // Act
        let result = DenIPCTargetResolver.resolveBoard(
            target: .automatic,
            context: DenIPCCallerContext(profileID: profile2.id.rawValue),
            kind: .web,
            in: manager
        )

        // Assert
        let resolved = try result.get()
        #expect(resolved.board.id == board2ID)
        #expect(resolved.store === store2)
    }

    @Test func resolveTargetWebBoardFailsOnUnknownProfileUUID() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        _ = try #require(manager.store(for: manager.personalProfileID))

        let unknownProfileID = UUID()

        // Act
        let result = DenIPCTargetResolver.resolveBoard(
            target: .automatic,
            context: DenIPCCallerContext(profileID: unknownProfileID),
            kind: .web,
            in: manager
        )

        // Assert
        switch result {
        case .failure(let error):
            #expect(error == .profileNotFound(unknownProfileID.uuidString))
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
        // Act
        let result = DenIPCTargetResolver.resolveBoard(
            target: .automatic,
            context: DenIPCCallerContext(profileID: profileWithoutWindow.id.rawValue),
            kind: .web,
            in: manager
        )

        // Assert
        switch result {
        case .failure(let error):
            #expect(error == .profileHasNoActiveWindow(profileWithoutWindow.id.rawValue.uuidString))
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

        // Act
        let result = DenIPCTargetResolver.resolveBoard(
            target: .explicit(board1ID.rawValue),
            context: DenIPCCallerContext(profileID: profile2.id.rawValue),
            kind: .web,
            in: manager
        )

        // Assert
        switch result {
        case .failure(let error):
            #expect(error == .boardNotFound(board1ID.rawValue.uuidString))
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

        // Act
        let result = DenIPCTargetResolver.resolveBoard(
            target: .automatic,
            context: DenIPCCallerContext(
                profileID: profile2.id.rawValue, callerBoardID: terminalBoardID.rawValue),
            kind: .web,
            in: manager
        )

        // Assert
        let resolved = try result.get()
        #expect(resolved.board.id == webBoardID)
        #expect(resolved.store === store2)
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
            operation: .boardClose(target: .explicit(board2ID.rawValue)),
            context: DenIPCCallerContext(profileID: profile2.id.rawValue)
        )
        let response = await service.handleRequest(request).result

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
            operation: .boardClose(target: .explicit(board1ID.rawValue)),
            context: DenIPCCallerContext(profileID: profile2.id.rawValue)
        )
        let response = await service.handleRequest(request).result

        // Assert
        #expect(response.isOk == false)
        #expect(response.error?.contains("Board not found: \(board1ID.rawValue.uuidString)") == true)
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

        let request = DenIPCRequest(operation: .boardClose(target: .explicit(terminalBoardID.rawValue)))
        let response = await service.handleRequest(request).result

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
        let duplicateDeskID = DeskID()
        let board1ID = BoardID()
        let board2ID = BoardID()

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
        let profile1ID = ProfileID()
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
        let result1 = DenIPCTargetResolver.resolveBoard(
            target: .explicit(board1ID.rawValue), context: DenIPCCallerContext(), kind: .web, in: manager)

        // Assert: Resolved store must be store1 (which owns board1), NEVER store2
        let resolved1 = try #require(try? result1.get())
        #expect(resolved1.board.id == board1ID)
        #expect(resolved1.store === store1)
        #expect(resolved1.store.board(for: board1ID) != nil)

        // Act: Target board2 without explicit profileID
        let result2 = DenIPCTargetResolver.resolveBoard(
            target: .explicit(board2ID.rawValue), context: DenIPCCallerContext(), kind: .web, in: manager)

        // Assert: Resolved store must be store2 (which owns board2), NEVER store1
        let resolved2 = try #require(try? result2.get())
        #expect(resolved2.board.id == board2ID)
        #expect(resolved2.store === store2)
        #expect(resolved2.store.board(for: board2ID) != nil)
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
        let scopedResult = DenIPCTargetResolver.resolveBoard(
            target: .explicit(board2ID.rawValue),
            context: DenIPCCallerContext(profileID: profileID.rawValue),
            kind: .web,
            in: manager
        )

        // Act 2: Resolve without profileID
        let unscopedResult = DenIPCTargetResolver.resolveBoard(
            target: .explicit(board2ID.rawValue), context: DenIPCCallerContext(), kind: .web, in: manager)

        // Assert: Both must return the exact same store (storeWindow2 presenting desk2)
        let scoped = try #require(try? scopedResult.get())
        let unscoped = try #require(try? unscopedResult.get())

        #expect(scoped.board.id == board2ID)
        #expect(unscoped.board.id == board2ID)
        #expect(scoped.store === unscoped.store)
        #expect(scoped.store === storeWindow2)
        #expect(scoped.store.presentedDeskID == desk2ID)
    }

    @Test func resolveStoreAndDeskWithExplicitNonExistentDeskIDDoesNotFallback() throws {
        // Arrange
        let directory = temporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeProfileManager(directory: directory)
        let store = try #require(manager.store(for: manager.personalProfileID))
        _ = try #require(store.createBoard(urlString: "https://example.com/"))

        let nonExistentDeskID = UUID()

        // Act 1: Explicit non-existent deskID without profileID
        let result1 = DenIPCTargetResolver.resolveDesk(
            target: .explicit(nonExistentDeskID), context: DenIPCCallerContext(), in: manager)

        // Assert 1: Must fail, must NOT fall back to presented desk
        switch result1 {
        case .failure(let error):
            #expect(error == .noActiveDesk)
        case .success:
            Issue.record("Expected failure on non-existent desk ID")
        }

        // Act 2: Explicit non-existent deskID with profileID
        let result2 = DenIPCTargetResolver.resolveDesk(
            target: .explicit(nonExistentDeskID),
            context: DenIPCCallerContext(profileID: manager.personalProfileID.rawValue),
            in: manager
        )

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
        let preferences = AppPreferences(defaults: makeTestDefaults(suiteName: suiteName))
        let navigation = SheetNavigationManager(
            defaults: makeTestDefaults(suiteName: suiteName),
            scriptSource: "")
        return ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: preferences,
            removeDataStore: { _ in },
            initialProfile: initialProfile,
            websiteDataStore: { _ in .nonPersistent() })
    }
}
