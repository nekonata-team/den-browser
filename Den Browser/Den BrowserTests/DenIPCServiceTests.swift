import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenIPCServiceTests {
    @Test func healthCommandReturnsHealthyWithoutAnActiveProfile() async {
        let service = DenIPCService()
        let response = await service.handleRequest(DenIPCRequest(command: .health))

        #expect(response.isOk)
        #expect(response.message == nil)
    }

    @Test func webBoardCreationStartsRuntime() async throws {
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
        let response = await service.handleRequest(
            DenIPCRequest(
                command: .board(.web(.new(DenBoardWebNewPayload(url: "https://example.com/", focus: false))))
            )
        )

        // Assert
        let boardID = try #require(response.boardId.flatMap(UUID.init(uuidString:)))
        #expect(store.runtimes[boardID] != nil)
    }

    @Test func sheetOpenUsesSharedInputResolution() async throws {
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

        let hostnameResponse = await service.handleRequest(
            DenIPCRequest(
                command: .sheet(.open(DenSheetOpenPayload(url: "localhost:3000"))),
                boardID: boardID.uuidString))
        #expect(hostnameResponse.isOk)
        #expect(hostnameResponse.url == "https://localhost:3000/")

        let unsupportedResponse = await service.handleRequest(
            DenIPCRequest(
                command: .sheet(.open(DenSheetOpenPayload(url: "mailto:user@example.com"))),
                boardID: boardID.uuidString))
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

        let response = await service.handleRequest(
            DenIPCRequest(
                command: .drawer(.keep(DenDrawerKeepPayload(url: "example.com", title: nil)))))
        #expect(response.isOk)
        #expect(store.state.drawerItems.first?.url == URL(string: "https://example.com/"))

        let searchResponse = await service.handleRequest(
            DenIPCRequest(
                command: .drawer(.keep(DenDrawerKeepPayload(url: "search phrase", title: nil)))))
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
        let response = await service.handleRequest(
            DenIPCRequest(
                command: .drawer(.place(id: itemID.uuidString))
            )
        )

        // Assert
        let boardID = try #require(response.boardId.flatMap(UUID.init(uuidString:)))
        #expect(store.runtimes[boardID] != nil)
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
        let response = await service.handleRequest(
            DenIPCRequest(command: .profile(.list)))

        // Assert
        #expect(response.isOk)
        let profiles = try #require(response.profiles)
        #expect(profiles.count == 2)
        let personal = try #require(profiles.first(where: { $0.id == manager.personalProfileID.uuidString }))
        #expect(personal.hasWindow == true)
        let work = try #require(profiles.first(where: { $0.id == profile2.id.uuidString }))
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
            DenIPCRequest(command: .desk(.list), profileID: profile2.id.uuidString))

        // Assert
        #expect(response.isOk)
        let desks = try #require(response.desks)
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
        var openedProfileID: UUID?
        manager.openWindowAction = { route in
            openedProfileID = route.profileID
        }
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(
                command: .profile(.open(profileID: profile2.id.uuidString))
            )
        )

        // Assert
        #expect(response.isOk)
        #expect(response.message?.contains("Opened window for profile 'Work'") == true)
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
        let window = NSWindow()
        manager.register(window: window, for: route)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(
                command: .profile(.open(profileID: manager.personalProfileID.uuidString))
            )
        )

        // Assert
        #expect(response.isOk)
        #expect(response.message?.contains("Activated window") == true)
    }

    @Test func profileOpenCommandRejectsInvalidProfileID() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-profile-invalid-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "IPCServiceProfileInvalidPreferences-\(UUID().uuidString)"
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: SheetNavigationManager(
                defaults: makeTestDefaults(suiteName: suiteName),
                scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() })
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(
                command: .profile(.open(profileID: "not-a-valid-uuid"))
            )
        )

        // Assert
        #expect(response.isOk == false)
        #expect(response.error?.contains("Invalid profile ID") == true)
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
        let unknownUUID = UUID().uuidString

        // Act
        let response = await service.handleRequest(
            DenIPCRequest(
                command: .profile(.open(profileID: unknownUUID))
            )
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
        let response = await service.handleRequest(DenIPCRequest(command: .board(.list)))

        // Assert
        #expect(response.isOk)
        let boards = try #require(response.boards)
        let matched = try #require(boards.first(where: { $0.id == boardID.uuidString }))
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
        let response = await service.handleRequest(DenIPCRequest(command: .board(.focused)))

        // Assert
        #expect(response.isOk)
        #expect(response.boardId == boardID.uuidString)
        let board = try #require(response.board)
        #expect(board.id == boardID.uuidString)
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
        let response = await service.handleRequest(DenIPCRequest(command: .board(.focused)))

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
        let runtime = store.runtime(for: board)

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
        let response = await service.handleRequest(
            DenIPCRequest(
                command: .sheet(
                    .click(
                        DenSheetClickPayload(
                            target: "#test-link",
                            role: nil,
                            name: nil,
                            exact: false,
                            newBoard: true,
                            focus: false
                        )
                    )
                ),
                boardID: boardID.uuidString
            )
        )

        // Assert
        #expect(response.isOk)
        let newBoardIDString = try #require(response.boardId)
        let newBoardUUID = try #require(UUID(uuidString: newBoardIDString))
        #expect(store.board(for: newBoardUUID) != nil)
        #expect(response.url == "https://example.com/subpage")
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
        let firstRuntime = store.runtime(for: firstBoard)
        let secondRuntime = store.runtime(for: secondBoard)
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
            ],
            full: false)

        // Act
        let interactTask = Task {
            await service.handleRequest(DenIPCRequest(command: .sheet(.interact(payload))))
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
        let firstRuntime = store.runtime(for: firstBoard)
        let secondRuntime = store.runtime(for: secondBoard)
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
            ],
            full: false)

        // Act
        let interactTask = Task {
            await service.handleRequest(
                DenIPCRequest(
                    command: .sheet(.interact(payload)),
                    boardID: firstBoardID.uuidString))
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
        #expect(response.error == "Target Web Board no longer exists: \(firstBoardID.uuidString)")
        #expect(response.completedActions == 1)
        #expect(response.failedActionIndex == 1)
    }
}
