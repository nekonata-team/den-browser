import DenDomain
import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenIPCServiceTests {
    @Test func healthCommandReturnsHealthyWithoutAnActiveProfile() async {
        let service = DenIPCService()
        let response = await service.handleResult(ipcRequest(.health))

        #expect(response.isOk)
        #expect(response.payload != nil)
        if case .empty = response.payload {
        } else {
            Issue.record("Expected empty health payload")
        }
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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            ipcRequest(
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
        let boardID = try responseBoardID(response)
        #expect(store.webRuntimes[boardID] != nil)
        #expect(store.board(for: boardID)?.width == 200)
    }

    @Test func ipcBoardPlacementUsesResolvedDeskWhenNoWindowPresentsIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-target-desk-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceTargetDeskPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let visibleDeskID = store.presentedDeskID
        let visibleBoardID = try #require(store.createBoard(urlString: "https://visible.example/"))
        store.createDesk(label: "Target Desk", preset: .empty)
        let targetDeskID = store.presentedDeskID
        #expect(targetDeskID != visibleDeskID)
        #expect(store.setFocusedDesk(visibleDeskID))
        let targetDeskIndex = try #require(store.state.desks.firstIndex(where: { $0.id == targetDeskID }))
        let drawerURL = try #require(URL(string: "https://drawer.example/"))
        let itemID = try #require(store.keepInDrawerInBackground(drawerURL))
        let service = DenIPCService(profileManager: manager)

        let webResponse = await service.handleResult(
            ipcRequest(
                .createWebBoard(
                    payload: DenBoardWebNewPayload(url: "https://web.example/", focus: false),
                    destination: .explicit(targetDeskID.rawValue)
                ),
                callerBoardID: visibleBoardID.rawValue
            ))
        let terminalResponse = await service.handleResult(
            ipcRequest(
                .createTerminalBoard(
                    payload: DenBoardTerminalNewPayload(path: nil, runCommand: nil, focus: false),
                    destination: .explicit(targetDeskID.rawValue)
                )))
        let drawerResponse = await service.handleResult(
            ipcRequest(.drawer(command: .place(id: itemID.uuidString), target: .explicit(targetDeskID.rawValue))))

        let webBoardID = try responseBoardID(webResponse)
        let terminalBoardID = try responseBoardID(terminalResponse)
        let drawerBoardID = try responseBoardID(drawerResponse)
        #expect(webResponse.isOk)
        #expect(terminalResponse.isOk)
        #expect(drawerResponse.isOk)
        #expect(store.boardIndices(for: webBoardID)?.desk == targetDeskIndex)
        #expect(store.boardIndices(for: terminalBoardID)?.desk == targetDeskIndex)
        #expect(store.boardIndices(for: drawerBoardID)?.desk == targetDeskIndex)
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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let targetBoardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let focusedBoardID = store.state.desks.first?.focusedBoardID
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            ipcRequest(
                .createInspectionBoard(
                    targetBoardID: targetBoardID.rawValue,
                    payload: DenBoardInspectionNewPayload(focus: false)
                )))
        let result = response.result

        // Assert
        let inspectionBoardID = try responseBoardID(result)
        let inspectionBoard = try #require(store.board(for: inspectionBoardID))
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
        #expect(store.state.desks.first?.focusedBoardID == focusedBoardID)
        #expect(store.webRuntimes[targetBoardID]?.isInspectionCollecting == true)
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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)

        let response = await service.handleResult(
            ipcRequest(
                .createTerminalBoard(
                    payload: DenBoardTerminalNewPayload(
                        path: nil,
                        runCommand: nil,
                        focus: false,
                        width: 1_500
                    ),
                    destination: .automatic
                ))
        )
        let terminalID = try responseBoardID(response)
        #expect(store.board(for: terminalID)?.width == 1_500)
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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)
        let staleBoardID = UUID()

        // Act
        let webResponse = await service.handleResult(
            ipcRequest(
                .createWebBoard(
                    payload: DenBoardWebNewPayload(url: "https://example.com/", focus: false),
                    destination: .automatic
                ),
                callerBoardID: staleBoardID
            ))
        let terminalResponse = await service.handleResult(
            ipcRequest(
                .createTerminalBoard(
                    payload: DenBoardTerminalNewPayload(path: nil, runCommand: nil, focus: false),
                    destination: .automatic
                ),
                callerBoardID: staleBoardID
            ))

        // Assert
        let webBoardID = try responseBoardID(webResponse)
        let terminalBoardID = try responseBoardID(terminalResponse)
        #expect(webResponse.isOk)
        #expect(terminalResponse.isOk)
        #expect(store.board(for: webBoardID)?.isWeb == true)
        #expect(store.board(for: terminalBoardID)?.isTerminal == true)
    }

    @Test func sheetNavigateUsesSharedInputResolution() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-sheet-open-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceSheetOpenPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        let hostnameResponse = await service.handleResult(
            ipcRequest(
                .sheet(
                    command: .navigate(DenSheetNavigatePayload(url: "localhost:3000")),
                    target: .explicit(boardID.rawValue)
                ))
        )
        #expect(hostnameResponse.isOk)
        guard case .navigation(_, let url) = try #require(hostnameResponse.payload) else {
            Issue.record("Expected navigation payload")
            return
        }
        #expect(url == "https://localhost:3000/")

        let unsupportedResponse = await service.handleResult(
            ipcRequest(
                .sheet(
                    command: .navigate(DenSheetNavigatePayload(url: "mailto:user@example.com")),
                    target: .explicit(boardID.rawValue)
                )))
        #expect(unsupportedResponse.isOk == false)
    }

    @Test func drawerKeepAcceptsURLsButRejectsSearchTerms() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-drawer-keep-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceDrawerKeepPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let service = DenIPCService(profileManager: manager)

        let response = await service.handleResult(
            ipcRequest(
                .drawer(command: .keep(DenDrawerKeepPayload(url: "example.com", title: nil)), target: .automatic)))
        #expect(response.isOk)
        #expect(store.state.drawerItems.first?.url == URL(string: "https://example.com/"))

        let searchResponse = await service.handleResult(
            ipcRequest(
                .drawer(command: .keep(DenDrawerKeepPayload(url: "search phrase", title: nil)), target: .automatic)))
        #expect(searchResponse.isOk == false)
        #expect(store.state.drawerItems.count == 1)
    }

    @Test func drawerPlacementStartsWebRuntime() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServicePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let itemID = try #require(
            store.keepInDrawerInBackground(URL(string: "https://example.com/drawer")!))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            ipcRequest(.drawer(command: .place(id: itemID.uuidString), target: .automatic))
        )

        // Assert
        let boardID = try responseBoardID(response)
        #expect(store.webRuntimes[boardID] != nil)
    }

    @Test func profileListCommandReturnsAllProfiles() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServicePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        _ = try #require(manager.store(for: manager.personalProfileID))
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            ipcRequest(.profileList))

        // Assert
        #expect(response.isOk)
        guard case .profiles(let profiles) = try #require(response.payload) else {
            Issue.record("Expected profile list payload")
            return
        }
        #expect(profiles.count == 2)
        let personal = try #require(profiles.first(where: { $0.id == manager.personalProfileID.rawValue.uuidString }))
        #expect(personal.hasWindow == true)
        let work = try #require(profiles.first(where: { $0.id == profile2.id.rawValue.uuidString }))
        #expect(work.name == "Work")
        #expect(work.hasWindow == false)
    }

    @Test func deskListCommandWithProfileIDReturnsDesksForTargetProfile() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-desk-profile-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceDeskPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        _ = try #require(manager.store(for: manager.personalProfileID))
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        let store2 = try #require(manager.store(for: profile2.id))
        store2.createDesk(label: "Work Desk", preset: .empty)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            ipcRequest(
                .deskList(target: .automatic), profileID: profile2.id.rawValue))
        let result = response.result

        // Assert
        #expect(result.isOk)
        if case .profile(let profileID) = response.target {
            #expect(profileID == profile2.id.rawValue)
        } else {
            Issue.record("Expected the resolved Profile target")
        }
        guard case .desks(let desks) = try #require(result.payload) else {
            Issue.record("Expected Desk list payload")
            return
        }
        #expect(desks.contains(where: { $0.label == "Work Desk" }))
    }

    @Test func profileOpenCommandOpensWindowWhenClosed() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-profile-open-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceProfileOpenPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        var openedProfileID: ProfileID?
        manager.openWindowAction = { route in
            openedProfileID = route.profileID
        }
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(ipcRequest(.openProfile(profileID: profile2.id.rawValue)))
        let result = response.result

        // Assert
        #expect(result.isOk)
        if case .profile(let profileID) = response.target {
            #expect(profileID == profile2.id.rawValue)
        } else {
            Issue.record("Expected the opened Profile target")
        }
        guard case .message(let message) = result.payload else {
            Issue.record("Expected profile-open message payload")
            return
        }
        #expect(message.contains("Opened window for profile 'Work'"))
        #expect(openedProfileID == profile2.id)
    }

    @Test func profileOpenCommandActivatesExistingWindow() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-profile-activate-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceProfileActivatePreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let route = ProfileWindowRoute(profileID: manager.personalProfileID)
        _ = try #require(manager.store(for: route))
        let window = TestWindow()
        manager.register(window: window, for: route)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            ipcRequest(.openProfile(profileID: manager.personalProfileID.rawValue))
        )

        // Assert
        #expect(response.isOk)
        guard case .message(let message) = try #require(response.payload) else {
            Issue.record("Expected profile-open message payload")
            return
        }
        #expect(message.contains("Activated window"))
        #expect(window.presentationRequests == 1)
    }

    @Test func profileOpenCommandFailsForUnknownProfileID() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-profile-unknown-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceProfileUnknownPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let service = DenIPCService(profileManager: manager)
        let unknownUUID = UUID()

        // Act
        let response = await service.handleResult(
            ipcRequest(.openProfile(profileID: unknownUUID))
        )

        // Assert
        #expect(response.isOk == false)
        #expect(response.error?.contains("Profile not found") == true)
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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        store.focusBoard(boardID)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(ipcRequest(.boardList(target: .automatic)))

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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        store.focusBoard(boardID)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(ipcRequest(.boardFocused(target: .automatic)))

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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        // Remove existing default boards if any
        if let focused = store.focusedBoard {
            store.removeBoard(focused.id)
        }
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(ipcRequest(.boardFocused(target: .automatic)))

        // Assert
        #expect(response.isOk == false)
        #expect(response.error?.contains("No focused Board found") == true)
    }

    @Test func sheetClickWithNewBoardCreatesWebBoard() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-sheet-click-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceSheetClickPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let board = try #require(store.board(for: boardID))
        let runtime = store.webRuntime(for: board)

        let waiter = SheetInteractionWebViewLoadWaiter()
        let html = """
            <!DOCTYPE html>
            <html>
            <body>
                <a id="test-link" href="https://example.com/subpage">Subpage</a>
            </body>
            </html>
            """
        await waiter.load(html, baseURL: URL(string: "https://example.com")!, in: runtime.webView)

        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            ipcRequest(
                .sheet(
                    command: .click(
                        DenSheetClickPayload(
                            target: "#test-link",
                            role: nil,
                            name: nil,
                            exact: false,
                            newBoard: true,
                            focus: false
                        )),
                    target: .explicit(boardID.rawValue)
                ))
        )

        // Assert
        #expect(response.isOk)
        guard case .createdBoard(let newBoardIDString, _, let url) = try #require(response.payload) else {
            Issue.record("Expected created Board payload")
            return
        }
        let newBoardID = BoardID(try #require(UUID(uuidString: newBoardIDString)))
        #expect(store.board(for: newBoardID) != nil)
        #expect(url == "https://example.com/subpage")
    }

    @Test func sheetCommandCanReturnSnapshotWithItsOriginalResult() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-sheet-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceSheetSnapshotPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://snapshot.example/"))
        let board = try #require(store.board(for: boardID))
        let runtime = store.webRuntime(for: board)
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            """
            <!doctype html>
            <body><button id="continue">Before</button></body>
            """,
            baseURL: URL(string: "https://snapshot.example/")!,
            in: runtime.webView)
        let service = DenIPCService(profileManager: manager)

        // Act
        let script = "document.querySelector('button').textContent = 'After'; 'eval-result'"
        let response = await service.handleRequest(
            ipcRequest(
                .sheetWithSnapshot(
                    command: .eval(DenSheetEvalPayload(script: script)),
                    target: .explicit(boardID.rawValue),
                    snapshot: DenSheetSnapshotPayload(full: false)
                )))
        let result = response.result

        // Assert
        #expect(result.isOk)
        if case .value(let value) = result.payload {
            #expect(value == "eval-result")
        } else {
            Issue.record("Expected evaluated value payload")
        }
        #expect(result.snapshot?.contains("After") == true)
        if case .board(let profileID, let resolvedBoardID) = response.target {
            #expect(profileID == manager.personalProfileID.rawValue)
            #expect(resolvedBoardID == boardID.rawValue)
        } else {
            Issue.record("Expected the Sheet Board as the response target")
        }
    }

    @Test func sheetInteractKeepsInitialBoardWhenFocusChangesDuringWait() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-interact-focus-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceInteractFocusPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let firstBoardID = try #require(store.createBoard(urlString: "https://first.example/"))
        let secondBoardID = try #require(store.createBoard(urlString: "https://second.example/"))
        store.focusBoard(firstBoardID)
        let firstBoard = try #require(store.board(for: firstBoardID))
        let secondBoard = try #require(store.board(for: secondBoardID))
        let firstRuntime = store.webRuntime(for: firstBoard)
        let secondRuntime = store.webRuntime(for: secondBoard)
        let firstWaiter = SheetInteractionWebViewLoadWaiter()
        let secondWaiter = SheetInteractionWebViewLoadWaiter()
        await firstWaiter.load(
            """
            <!doctype html>
            <body>
              <button id="continue" onclick="this.textContent = 'Clicked'">Continue</button>
              <script>window.waitStarted = null; window.targetReady = null;</script>
            </body>
            """,
            baseURL: URL(string: "https://first.example/")!,
            in: firstRuntime.webView)
        await secondWaiter.load(
            """
            <!doctype html>
            <body><p>Second Board</p></body>
            """,
            baseURL: URL(string: "https://second.example/")!,
            in: secondRuntime.webView)
        let service = DenIPCService(profileManager: manager)
        let readyToken = UUID().uuidString
        let payload = DenSheetInteractPayload(
            steps: [
                DenSheetInteractStep(
                    line: 1,
                    text: "wait",
                    command: .wait(
                        DenSheetWaitPayload(
                            target: nil,
                            state: nil,
                            url: nil,
                            text: nil,
                            loadState: nil,
                            function: "window.waitStarted = '\(readyToken)', window.targetReady === '\(readyToken)'",
                            timeout: 2))),
                DenSheetInteractStep(
                    line: 2,
                    text: "click #continue",
                    command: .click(
                        DenSheetClickPayload(
                            target: "#continue",
                            role: nil,
                            name: nil,
                            exact: false,
                            newBoard: false,
                            focus: false,
                        ))),
            ])

        // Act
        let interactTask = Task {
            await service.handleResult(
                ipcRequest(
                    .sheetWithSnapshot(
                        command: .interact(payload),
                        target: .automatic,
                        snapshot: DenSheetSnapshotPayload(full: false)
                    )))
        }
        var waitStarted = false
        for _ in 0..<100 {
            let value = try? await firstRuntime.webView.evaluateJavaScript(
                "window.waitStarted === '\(readyToken)'")
            waitStarted = (value as? Bool) == true
            if waitStarted { break }
            await Task.yield()
        }
        #expect(waitStarted)
        store.focusBoard(secondBoardID)
        _ = try await firstRuntime.webView.evaluateJavaScript(
            "window.targetReady = '\(readyToken)'")
        let response = await interactTask.value

        // Assert
        #expect(response.isOk)
        #expect(response.completedActions == 2)
        #expect(response.snapshot?.contains("Clicked") == true)
    }

    @Test func sheetInteractSnapshotsOnlyWhenRequested() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-interact-snapshot-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceInteractSnapshotPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://interact.example/"))
        let board = try #require(store.board(for: boardID))
        let webView = store.webRuntime(for: board).webView
        let waiter = SheetInteractionWebViewLoadWaiter()
        await waiter.load(
            "<!doctype html><body><button id=\"continue\">Continue</button><h2>Static detail</h2></body>",
            baseURL: URL(string: "https://interact.example/")!,
            in: webView)
        let service = DenIPCService(profileManager: manager)

        func request(target: String, snapshot: DenSheetSnapshotPayload? = nil) -> DenIPCRequest {
            let command = DenIPCCommand.Sheet.interact(
                DenSheetInteractPayload(
                    steps: [
                        DenSheetInteractStep(
                            line: 1,
                            text: "click \(target)",
                            command: .click(
                                DenSheetClickPayload(
                                    target: target,
                                    role: nil,
                                    name: nil,
                                    exact: false,
                                    newBoard: false,
                                    focus: false)))
                    ]))
            let operation: DenIPCOperation
            if let snapshot {
                operation = .sheetWithSnapshot(
                    command: command,
                    target: .explicit(boardID.rawValue),
                    snapshot: snapshot
                )
            } else {
                operation = .sheet(command: command, target: .explicit(boardID.rawValue))
            }
            return ipcRequest(operation)
        }

        // Act
        let success = await service.handleResult(request(target: "#continue"))
        let failure = await service.handleResult(request(target: "#missing"))
        let successWithSnapshot = await service.handleResult(
            request(target: "#continue", snapshot: DenSheetSnapshotPayload(full: false)))
        let failureWithSnapshotReply = await service.handleRequest(
            request(target: "#missing", snapshot: DenSheetSnapshotPayload(full: false)))
        let failureWithSnapshot = failureWithSnapshotReply.result
        let fullSnapshot = await service.handleResult(
            request(target: "#continue", snapshot: DenSheetSnapshotPayload(full: true)))

        // Assert
        #expect(success.isOk)
        #expect(success.snapshot == nil)
        #expect(success.completedActions == 1)
        #expect(failure.isOk == false)
        #expect(failure.snapshot == nil)
        #expect(failure.completedActions == 0)
        #expect(failure.failedActionIndex == 0)
        #expect(successWithSnapshot.isOk)
        #expect(successWithSnapshot.snapshot?.contains("Continue") == true)
        #expect(successWithSnapshot.snapshot?.contains("Static detail") == false)
        #expect(successWithSnapshot.completedActions == 1)
        #expect(failureWithSnapshot.isOk == false)
        #expect(failureWithSnapshot.snapshot?.contains("Continue") == true)
        #expect(failureWithSnapshot.completedActions == 0)
        #expect(failureWithSnapshot.failedActionIndex == 0)
        if case .board(let profileID, let targetBoardID) = failureWithSnapshotReply.target {
            #expect(profileID == manager.personalProfileID.rawValue)
            #expect(targetBoardID == boardID.rawValue)
        } else {
            Issue.record("Expected the failed Sheet action's resolved Board target")
        }
        #expect(fullSnapshot.isOk)
        #expect(fullSnapshot.snapshot?.contains("Static detail") == true)
    }

    @Test func sheetInteractFailsWhenInitialBoardDisappearsDuringWait() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-interact-removal-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceInteractRemovalPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let firstBoardID = try #require(store.createBoard(urlString: "https://first.example/"))
        let secondBoardID = try #require(store.createBoard(urlString: "https://second.example/"))
        store.focusBoard(firstBoardID)
        let firstBoard = try #require(store.board(for: firstBoardID))
        let secondBoard = try #require(store.board(for: secondBoardID))
        let firstRuntime = store.webRuntime(for: firstBoard)
        let secondRuntime = store.webRuntime(for: secondBoard)
        let firstWaiter = SheetInteractionWebViewLoadWaiter()
        let secondWaiter = SheetInteractionWebViewLoadWaiter()
        await firstWaiter.load(
            """
            <!doctype html>
            <body>
              <button id="continue">Continue</button>
              <script>window.waitStarted = null; window.targetReady = null;</script>
            </body>
            """,
            baseURL: URL(string: "https://first.example/")!,
            in: firstRuntime.webView)
        await secondWaiter.load(
            """
            <!doctype html>
            <body><button id="continue">Second Board</button></body>
            """,
            baseURL: URL(string: "https://second.example/")!,
            in: secondRuntime.webView)
        let service = DenIPCService(profileManager: manager)
        let readyToken = UUID().uuidString
        let payload = DenSheetInteractPayload(
            steps: [
                DenSheetInteractStep(
                    line: 1,
                    text: "wait",
                    command: .wait(
                        DenSheetWaitPayload(
                            target: nil,
                            state: nil,
                            url: nil,
                            text: nil,
                            loadState: nil,
                            function: "window.waitStarted = '\(readyToken)', window.targetReady === '\(readyToken)'",
                            timeout: 2))),
                DenSheetInteractStep(
                    line: 2,
                    text: "click #continue",
                    command: .click(
                        DenSheetClickPayload(
                            target: "#continue",
                            role: nil,
                            name: nil,
                            exact: false,
                            newBoard: false,
                            focus: false,
                        ))),
            ])

        // Act
        let interactTask = Task {
            await service.handleResult(
                ipcRequest(
                    .sheet(
                        command: .interact(payload), target: .explicit(firstBoardID.rawValue))))
        }
        var waitStarted = false
        for _ in 0..<100 {
            let value = try? await firstRuntime.webView.evaluateJavaScript(
                "window.waitStarted === '\(readyToken)'")
            waitStarted = (value as? Bool) == true
            if waitStarted { break }
            await Task.yield()
        }
        #expect(waitStarted)
        store.removeBoard(firstBoardID)
        store.focusBoard(secondBoardID)
        _ = try await firstRuntime.webView.evaluateJavaScript(
            "window.targetReady = '\(readyToken)'")
        let response = await interactTask.value

        // Assert
        #expect(response.isOk == false)
        #expect(response.error == "Target Web Board no longer exists: \(firstBoardID.rawValue.uuidString)")
        #expect(response.completedActions == 1)
        #expect(response.failedActionIndex == 1)
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
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let store = try #require(manager.store(for: manager.personalProfileID))
        let boardID = try #require(store.createBoard(urlString: "https://example.com/"))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            ipcRequest(.boardClose(target: .explicit(boardID.rawValue))))
        let result = response.result

        // Assert
        #expect(result.isOk)
        #expect(store.board(for: boardID) == nil)
        if case .board(let profileID, let targetBoardID) = response.target {
            #expect(profileID == manager.personalProfileID.rawValue)
            #expect(targetBoardID == boardID.rawValue)
        } else {
            Issue.record("Expected the closed Board as the response target")
        }
    }

    private func ipcRequest(
        _ operation: DenIPCOperation,
        profileID: UUID? = nil,
        callerBoardID: UUID? = nil
    ) -> DenIPCRequest {
        DenIPCRequest(
            operation: operation,
            context: DenIPCCallerContext(profileID: profileID, callerBoardID: callerBoardID)
        )
    }

    private func responseBoardID(_ response: DenIPCOperationResult) throws -> BoardID {
        let id: String
        if case .createdBoard(let boardID, _, _) = response.payload {
            id = boardID
        } else {
            Issue.record("Expected created Board payload")
            id = ""
        }
        return BoardID(try #require(UUID(uuidString: id)))
    }
}

private extension DenIPCService {
    func handleResult(_ request: DenIPCRequest) async -> DenIPCOperationResult {
        await handleRequest(request).result
    }
}
