import AppKit
import DenApplication
import DenDomain
import DenIPCProtocol
import DenInfrastructure
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct IPCBoardServiceTests {
    @Test(arguments: ["web", "terminal", "inspection", "tutorial"])
    func boardResizeUsesLiveWindowWidthAndPreservesSelection(kind: String) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let displayedDeskID = session.navigation.presentedDeskID
        session.desks.createDesk(label: "Target", preset: .empty)
        let primary = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let target: BoardID
        switch kind {
        case "terminal":
            target = try #require(session.boardOpening.createTerminalBoard(workingDirectory: "/tmp", focus: false))
        case "inspection":
            target = try #require(session.sideBoards.createInspectionBoard(targetBoardID: primary, focus: false))
        case "tutorial":
            #expect(session.boardOpening.openTutorialBoard())
            target = try #require(session.resources.state.desks.flatMap(\.boards).first(where: \.isTutorial)?.id)
        default:
            target = primary
        }
        let targetDeskID = session.navigation.presentedDeskID
        session.boardNavigation.focusDesk(displayedDeskID)
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        composition.model.updateBoardLayout(availableWidth: 960, spacing: 12)
        composition.model.maximizedBoardID = target
        let service = DenIPCService(profileManager: manager)
        let selection = session.resources.state.desks.first(where: { $0.id == targetDeskID })?.focusedBoardID
        let neighbors = session.resources.state.desks.flatMap(\.boards).filter { $0.id != target }

        // Act / Assert
        for (requested, expected) in [(2_000.0, 960.0), (1.0, 280.0), (640.0, 640.0), (2_000.0, 1_800.0)] {
            if expected == 1_800 {
                composition.model.updateBoardLayout(availableWidth: 1_800, spacing: 12)
            }
            let result = await service.handleResult(
                makeIPCRequest(.resizeBoard(boardID: target.rawValue, width: requested))
            )
            guard case .resizedBoard(let id, let width) = result.payload else {
                Issue.record("Expected applied width: \(result.error ?? "missing result")")
                return
            }
            #expect(result.isOk)
            #expect(id == target.rawValue.uuidString)
            #expect(width == expected)
            #expect(session.resources.state.board(for: target)?.width == expected)
        }
        #expect(composition.model.maximizedBoardID == nil)
        #expect(session.navigation.presentedDeskID == displayedDeskID)
        #expect(session.resources.state.desks.first(where: { $0.id == targetDeskID })?.focusedBoardID == selection)
        #expect(session.resources.state.desks.flatMap(\.boards).filter { $0.id != target } == neighbors)
        let persisted = ProfilePersistence(
            directoryURL: directory,
            isEphemeral: false,
            quarantineFile: { try FileManager.default.moveItem(at: $0, to: $1) }
        ).load()
        let restored = persisted.profiles.first(where: { $0.profile.id == manager.personalProfileID })?.den.board(
            for: target
        )
        #expect(kind == "tutorial" ? restored == nil : restored?.width == 1_800)
    }

    @Test(arguments: ["missing", "layout", "narrow", "invalid"])
    func boardResizeFailurePreservesState(reason: String) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let board = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        session.connection.availableBoardWidth = { reason == "layout" ? nil : (reason == "narrow" ? 200 : 960) }
        let before = session.resources.state
        let service = DenIPCService(profileManager: manager)

        // Act
        let result = await service.handleResult(
            makeIPCRequest(
                .resizeBoard(
                    boardID: reason == "missing" ? UUID() : board.rawValue,
                    width: reason == "invalid" ? 0 : 800
                )
            )
        )

        // Assert
        #expect(!result.isOk)
        #expect(session.resources.state == before)
    }

    @Test(arguments: ["web", "terminal"], [false, true])
    func boardCreationRejectsMissingRelativeAnchor(kind: String, left: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let before = session.resources.state
        let destination: DenBoardCreationDestination = left ? .leftOf(UUID()) : .rightOf(UUID())
        let operation: DenIPCOperation =
            kind == "web"
            ? .createWebBoard(payload: .init(url: "https://example.com/", focus: false), destination: destination)
            : .createTerminalBoard(payload: .init(path: nil, runCommand: nil, focus: false), destination: destination)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(makeIPCRequest(operation))

        // Assert
        #expect(!response.isOk)
        #expect(session.resources.state == before)
    }

    @Test(arguments: ["left", "right", "desk"], [false, true])
    func boardMovePlacesWholeGroupAtExplicitDestination(position: String, sameDesk: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let sourceDeskID = session.navigation.presentedDeskID
        let moved = try #require(session.boardOpening.createBoard(urlString: "https://example.com/moved"))
        let side = try #require(session.sideBoards.createInspectionBoard(targetBoardID: moved, focus: false))
        if !sameDesk { session.desks.createDesk(label: "Target", preset: .empty) }
        let targetDeskID = session.navigation.presentedDeskID
        let anchor = try #require(session.boardOpening.createBoard(urlString: "https://example.com/anchor"))
        let anchorSide = try #require(session.sideBoards.createInspectionBoard(targetBoardID: anchor, focus: false))
        let tail = try #require(
            session.boardOpening.createBoard(urlString: "https://example.com/tail", focus: false)
        )
        session.boardNavigation.focusDesk(sourceDeskID)
        let destination: DenBoardMoveDestination
        switch position {
        case "left": destination = .leftOf(anchorSide.rawValue)
        case "right": destination = .rightOf(anchorSide.rawValue)
        default: destination = .endOfDesk(targetDeskID.rawValue)
        }
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(.moveBoard(boardID: side.rawValue, destination: destination))
        )

        // Assert
        #expect(response.isOk)
        #expect(session.navigation.presentedDeskID == sourceDeskID)
        let target = try #require(session.resources.state.desks.first(where: { $0.id == targetDeskID }))
        let groupIDs = [moved, side]
        let anchorIDs = [anchor, anchorSide]
        let expected =
            position == "left"
            ? groupIDs + anchorIDs + [tail]
            : position == "right" ? anchorIDs + groupIDs + [tail] : anchorIDs + [tail] + groupIDs
        #expect(target.boards.map(\.id) == expected)
        #expect(target.focusedBoardID == anchor)
    }

    @Test(arguments: ["source", "desk", "left", "right", "same-group"])
    func boardMoveDoesNotMutateStateForUnavailableTargetsOrItsOwnGroup(target: String) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = makeTestDefaults()
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(defaults: defaults, scriptSource: ""),
            preferences: AppPreferences(defaults: defaults),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let sideID = try #require(session.sideBoards.createInspectionBoard(targetBoardID: boardID, focus: false))
        let before = session.resources.state
        let destination: DenBoardMoveDestination
        switch target {
        case "desk": destination = .endOfDesk(UUID())
        case "left": destination = .leftOf(UUID())
        case "right": destination = .rightOf(UUID())
        case "same-group": destination = .rightOf(sideID.rawValue)
        default: destination = .endOfDesk(session.navigation.presentedDeskID.rawValue)
        }
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(
                .moveBoard(
                    boardID: target == "source" ? UUID() : boardID.rawValue,
                    destination: destination
                )
            )
        )

        // Assert
        #expect(response.isOk == (target == "same-group"))
        #expect(session.resources.state == before)
    }

    @Test(arguments: [false, true])
    func cancellingSaveDialogRequiresItsOwningBoard(differentBoard: Bool) async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "DialogIPC-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let ownerID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let otherID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/other"))
        let board = try #require(session.resources.state.board(for: ownerID))
        let runtime = session.runtimes.webRuntime(for: board)
        defer { runtime.dispose() }
        var replies: [URL?] = []
        let id = runtime.downloadHandler.saveDialogs.register(
            panel: NSSavePanel(),
            suggestedFilename: "report.pdf",
            downloadKey: ObjectIdentifier(runtime)
        ) { url, _ in replies.append(url) }
        let service = DenIPCService(profileManager: manager)
        // Act
        let response = await service.handleResult(
            makeIPCRequest(
                .sheet(
                    command: .dialog(.cancel(id: id)),
                    target: .explicit((differentBoard ? otherID : ownerID).rawValue)
                )
            )
        )

        // Assert
        #expect(response.isOk == !differentBoard)
        #expect(replies.count == (differentBoard ? 0 : 1))
        #expect(replies.allSatisfy { $0 == nil })
    }

    @Test func webBoardCreationUsesRequestedWidthAndStartsRuntime() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServicePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(
                .createWebBoard(
                    payload: DenBoardWebNewPayload(
                        url: "https://example.com/",
                        focus: false,
                        width: 200
                    ),
                    destination: .automatic
                )
            )
        )

        // Assert
        let boardID = try extractCreatedBoardID(response)
        #expect(session.resources.webRuntimes[boardID] != nil)
        #expect(session.resources.state.board(for: boardID)?.width == 200)
    }

    @Test func inspectionBoardCreationUsesExplicitTargetWithoutChangingFocus() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-inspection-board-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceInspectionPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let targetBoardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let focusedBoardID = session.resources.state.desks.first?.focusedBoardID
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            makeIPCRequest(
                .createInspectionBoard(
                    targetBoardID: targetBoardID.rawValue,
                    payload: DenBoardInspectionNewPayload(focus: false)
                )
            )
        )
        let result = response.result

        // Assert
        let inspectionBoardID = try extractCreatedBoardID(result)
        let inspectionBoard = try #require(session.resources.state.board(for: inspectionBoardID))
        #expect(result.isOk)
        if case .board(let profileID, let resolvedBoardID) = response.target {
            #expect(profileID == manager.personalProfileID.rawValue)
            #expect(resolvedBoardID == targetBoardID.rawValue)
        } else {
            Issue.record("Expected the source Web Board as the response target")
        }
        #expect(inspectionBoardID != targetBoardID)
        if case .createdBoard(let id, _, _) = result.payload {
            #expect(id == inspectionBoardID.rawValue.uuidString)
        } else {
            Issue.record("Expected created Inspection Board payload")
        }
        #expect(inspectionBoard.sideBoardTargetBoardID == targetBoardID)
        #expect(session.resources.state.desks.first?.focusedBoardID == focusedBoardID)
        #expect(session.resources.webRuntimes[targetBoardID]?.isInspectionCollecting == true)
    }

    @Test func terminalBoardCreationUsesRequestedWidth() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-terminal-board-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceTerminalPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)

        let response = await service.handleResult(
            makeIPCRequest(
                .createTerminalBoard(
                    payload: DenBoardTerminalNewPayload(
                        path: nil,
                        runCommand: nil,
                        focus: false,
                        width: 1_500
                    ),
                    destination: .automatic
                )
            )
        )
        let terminalID = try extractCreatedBoardID(response)
        #expect(session.resources.state.board(for: terminalID)?.width == 1_500)
    }

    @Test func boardCreationFallsBackWhenAmbientBoardIDIsStale() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-stale-board-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceStaleBoardPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)
        let staleBoardID = UUID()

        // Act
        let webResponse = await service.handleResult(
            makeIPCRequest(
                .createWebBoard(
                    payload: DenBoardWebNewPayload(url: "https://example.com/", focus: false),
                    destination: .automatic
                ),
                callerBoardID: staleBoardID
            )
        )
        let terminalResponse = await service.handleResult(
            makeIPCRequest(
                .createTerminalBoard(
                    payload: DenBoardTerminalNewPayload(path: nil, runCommand: nil, focus: false),
                    destination: .automatic
                ),
                callerBoardID: staleBoardID
            )
        )

        // Assert
        let webBoardID = try extractCreatedBoardID(webResponse)
        let terminalBoardID = try extractCreatedBoardID(terminalResponse)
        #expect(webResponse.isOk)
        #expect(terminalResponse.isOk)
        #expect(session.resources.state.board(for: webBoardID)?.isWeb == true)
        #expect(session.resources.state.board(for: terminalBoardID)?.isTerminal == true)
    }

    @Test func boardListCommandIncludesFocusedState() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-board-list-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceBoardListPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        session.boardNavigation.focusBoard(boardID)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(makeIPCRequest(.boardList(target: .automatic)))

        // Assert
        #expect(response.isOk)
        guard case .boards(let boards) = try #require(response.payload) else {
            Issue.record("Expected Board list payload")
            return
        }
        let matched = try #require(boards.first(where: { $0.id == boardID.rawValue.uuidString }))
        #expect(matched.isFocused == true)
    }

    @Test func boardFocusedCommandReturnsCurrentlyFocusedBoard() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-board-focused-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceBoardFocusedPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        session.boardNavigation.focusBoard(boardID)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(makeIPCRequest(.boardFocused(target: .automatic)))

        // Assert
        #expect(response.isOk)
        guard case .board(let board) = try #require(response.payload) else {
            Issue.record("Expected Board payload")
            return
        }
        #expect(board.id == boardID.rawValue.uuidString)
        #expect(board.isFocused == true)
        #expect(board.type == "web")
    }

    @Test func boardFocusedCommandFailsWhenNoBoardsExist() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-board-none-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceBoardNonePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        // Remove existing default boards if any
        if let focused = session.navigation.focusedBoard {
            session.boardRemoval.removeBoard(focused.id)
        }
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(makeIPCRequest(.boardFocused(target: .automatic)))

        // Assert
        #expect(response.isOk == false)
        #expect(response.error?.contains("No focused Board found") == true)
    }

    @Test func boardCloseReturnsContextFromTheClosedBoard() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-close-context-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceCloseContextPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            makeIPCRequest(.boardClose(target: .explicit(boardID.rawValue)))
        )
        let result = response.result

        // Assert
        #expect(result.isOk)
        #expect(session.resources.state.board(for: boardID) == nil)
        if case .board(let profileID, let targetBoardID) = response.target {
            #expect(profileID == manager.personalProfileID.rawValue)
            #expect(targetBoardID == boardID.rawValue)
        } else {
            Issue.record("Expected the closed Board as the response target")
        }
    }
}
