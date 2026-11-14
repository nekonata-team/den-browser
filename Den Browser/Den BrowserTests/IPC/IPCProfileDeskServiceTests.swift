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
struct IPCProfileDeskServiceTests {
    @Test(
        arguments: [("web", false), ("web", true), ("terminal", false), ("terminal", true)],
        ["left", "right", "end"]
    )
    func boardCreationRespectsPlacementOnAnotherDesk(creation: (String, Bool), position: String) async throws {
        // Arrange
        let (kind, focus) = creation
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
        let caller = try #require(session.boardOpening.createBoard(urlString: "https://example.com/caller"))
        session.desks.createDesk(label: "Target", preset: .empty)
        let targetDeskID = session.navigation.presentedDeskID
        let anchor = try #require(session.boardOpening.createBoard(urlString: "https://example.com/anchor"))
        let side = try #require(session.sideBoards.createInspectionBoard(targetBoardID: anchor, focus: false))
        let tail = try #require(session.boardOpening.createBoard(urlString: "https://example.com/tail", focus: false))
        session.boardNavigation.focusDesk(sourceDeskID)
        let destination: DenBoardCreationDestination =
            switch position {
            case "left": .leftOf(side.rawValue)
            case "right": .rightOf(side.rawValue)
            default: .endOfDesk(targetDeskID.rawValue)
            }
        let operation: DenIPCOperation =
            kind == "web"
            ? .createWebBoard(payload: .init(url: "https://example.com/new", focus: focus), destination: destination)
            : .createTerminalBoard(payload: .init(path: nil, runCommand: nil, focus: focus), destination: destination)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(operation, callerBoardID: (position == "end" ? anchor : caller).rawValue)
        )

        // Assert
        let created = try extractCreatedBoardID(response)
        let target = try #require(session.resources.state.desks.first(where: { $0.id == targetDeskID }))
        let expectedOrder =
            switch position {
            case "left": [created, anchor, side, tail]
            case "right": [anchor, side, created, tail]
            default: [anchor, side, tail, created]
            }
        #expect(target.boards.map(\.id) == expectedOrder)
        #expect(target.focusedBoardID == (focus ? created : anchor))
        #expect(session.navigation.presentedDeskID == (focus ? targetDeskID : sourceDeskID))
        #expect(session.resources.state.board(for: created)?.isWeb == (kind == "web"))
    }

    @Test(arguments: ["web", "terminal"], [false, true])
    func boardCreationUsesCallerUnlessEndOfDeskIsExplicit(kind: String, append: Bool) async throws {
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
        let deskID = session.navigation.presentedDeskID
        let caller = try #require(session.boardOpening.createBoard(urlString: "https://example.com/caller"))
        let tail = try #require(session.boardOpening.createBoard(urlString: "https://example.com/tail", focus: false))
        let destination: DenBoardCreationDestination = append ? .endOfDesk(deskID.rawValue) : .automatic
        let operation: DenIPCOperation =
            kind == "web"
            ? .createWebBoard(payload: .init(url: "https://example.com/new", focus: false), destination: destination)
            : .createTerminalBoard(payload: .init(path: nil, runCommand: nil, focus: false), destination: destination)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(makeIPCRequest(operation, callerBoardID: caller.rawValue))

        // Assert
        let created = try extractCreatedBoardID(response)
        let desk = try #require(session.resources.state.desks.first(where: { $0.id == deskID }))
        #expect(desk.boards.map(\.id) == (append ? [caller, tail, created] : [caller, created, tail]))
        #expect(desk.focusedBoardID == caller)
    }

    @Test func healthCommandReturnsHealthyWithoutAnActiveProfile() async {
        let service = DenIPCService()
        let response = await service.handleResult(makeIPCRequest(.health))

        #expect(response.isOk)
        #expect(response.payload != nil)
        if case .empty = response.payload {
        } else {
            Issue.record("Expected empty health payload")
        }
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
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let visibleDeskID = session.navigation.presentedDeskID
        let visibleBoardID = try #require(session.boardOpening.createBoard(urlString: "https://visible.example/"))
        session.desks.createDesk(label: "Target Desk", preset: .empty)
        let targetDeskID = session.navigation.presentedDeskID
        #expect(targetDeskID != visibleDeskID)
        #expect(session.boardNavigation.setFocusedDesk(visibleDeskID))
        let targetDeskIndex = try #require(
            session.resources.state.desks.firstIndex(where: { $0.id == targetDeskID })
        )
        let drawerURL = try #require(URL(string: "https://drawer.example/"))
        let itemID = try #require(session.drawer.keepInDrawerInBackground(drawerURL))
        let service = DenIPCService(profileManager: manager)

        let webResponse = await service.handleResult(
            makeIPCRequest(
                .createWebBoard(
                    payload: DenBoardWebNewPayload(url: "https://web.example/", focus: false),
                    destination: .endOfDesk(targetDeskID.rawValue)
                ),
                callerBoardID: visibleBoardID.rawValue
            )
        )
        let terminalResponse = await service.handleResult(
            makeIPCRequest(
                .createTerminalBoard(
                    payload: DenBoardTerminalNewPayload(path: nil, runCommand: nil, focus: false),
                    destination: .endOfDesk(targetDeskID.rawValue)
                )
            )
        )
        let presentedAfterBackgroundCreation = session.navigation.presentedDeskID
        let focusedAfterBackgroundCreation = session.navigation.focusedBoard?.id
        let drawerResponse = await service.handleResult(
            makeIPCRequest(.drawer(command: .place(id: itemID.uuidString), target: .explicit(targetDeskID.rawValue)))
        )

        let webBoardID = try extractCreatedBoardID(webResponse)
        let terminalBoardID = try extractCreatedBoardID(terminalResponse)
        let drawerBoardID = try extractCreatedBoardID(drawerResponse)
        #expect(webResponse.isOk)
        #expect(terminalResponse.isOk)
        let terminalRuntime = try #require(session.resources.terminalRuntimes[terminalBoardID])
        #expect(terminalRuntime.readText() != nil)
        #expect(terminalRuntime.terminalView.window == nil)
        #expect(drawerResponse.isOk)
        #expect(session.resources.state.boardIndices(for: webBoardID)?.deskOffset == targetDeskIndex)
        #expect(session.resources.state.boardIndices(for: terminalBoardID)?.deskOffset == targetDeskIndex)
        #expect(session.resources.state.boardIndices(for: drawerBoardID)?.deskOffset == targetDeskIndex)
        #expect(presentedAfterBackgroundCreation == visibleDeskID)
        #expect(focusedAfterBackgroundCreation == visibleBoardID)
    }

    @Test(arguments: ["text", "send", "run", "press"])
    func terminalCommandsStartUnpresentedSessionsWithoutChangingDesk(command: String) async throws {
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
        let visibleDeskID = session.navigation.presentedDeskID
        let visibleBoardID = session.navigation.focusedBoard?.id
        session.desks.createDesk(label: "Background", preset: .empty)
        let boardID = try #require(session.boardOpening.createTerminalBoard(workingDirectory: "/tmp", focus: false))
        #expect(session.boardNavigation.setFocusedDesk(visibleDeskID))
        let board = try #require(session.resources.state.board(for: boardID))
        let runtime = session.runtimes.terminalRuntime(for: board)
        defer { runtime.dispose() }
        #expect(runtime.readText() == nil)
        let service = DenIPCService(profileManager: manager)
        let operation: DenIPCCommand.Terminal
        if command == "press" {
            let invalid = await service.handleResult(
                makeIPCRequest(.terminal(command: .press(key: "Unknown"), target: .explicit(boardID.rawValue)))
            )
            #expect(!invalid.isOk)
            #expect(runtime.readText() == nil)
        }
        switch command {
        case "text": operation = .text()
        case "send": operation = .send(text: "den_cli_value=17")
        case "press": operation = .press(key: "Enter")
        default: operation = .run(command: "den_cli_value=17")
        }

        // Act
        let result = await service.handleResult(
            makeIPCRequest(.terminal(command: operation, target: .explicit(boardID.rawValue)))
        )
        #expect(result.isOk)
        #expect(runtime.readText() != nil)
        if command == "text" || command == "press" {
            runtime.runCommand("den_cli_value=17")
        }
        let continuation = command == "send" ? "; " : ""
        let followup = await service.handleResult(
            makeIPCRequest(
                .terminal(
                    command: .run(command: "\(continuation)printf 'ipc-result-%s\\n' \"$den_cli_value\""),
                    target: .explicit(boardID.rawValue)
                )
            )
        )
        let deadline = ContinuousClock.now + .seconds(5)
        while runtime.readText()?.contains("ipc-result-17") != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        // Assert
        #expect(followup.isOk)
        #expect(runtime.readText()?.contains("ipc-result-17") == true)
        #expect(runtime.terminalView.window == nil)
        #expect(session.navigation.presentedDeskID == visibleDeskID)
        #expect(session.navigation.focusedBoard?.id == visibleBoardID)
        session.boardRemoval.removeBoard(boardID)
        #expect(session.resources.terminalRuntimes[boardID] == nil)
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
                .drawer(command: .keep(DenDrawerKeepPayload(url: "example.com", title: nil)), target: .automatic)
            )
        )
        #expect(response.isOk)
        #expect(session.resources.state.drawerItems.first?.url == URL(string: "https://example.com/"))

        let searchResponse = await service.handleResult(
            makeIPCRequest(
                .drawer(command: .keep(DenDrawerKeepPayload(url: "search phrase", title: nil)), target: .automatic)
            )
        )
        #expect(searchResponse.isOk == false)
        #expect(session.resources.state.drawerItems.count == 1)
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
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let itemID = try #require(
            session.drawer.keepInDrawerInBackground(URL(string: "https://example.com/drawer")!)
        )
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(.drawer(command: .place(id: itemID.uuidString), target: .automatic))
        )

        // Assert
        let boardID = try extractCreatedBoardID(response)
        #expect(session.resources.webRuntimes[boardID] != nil)
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
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        _ = try #require(manager.session(for: manager.personalProfileID))
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(.profileList)
        )

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
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        _ = try #require(manager.session(for: manager.personalProfileID))
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        let session2 = try #require(manager.session(for: profile2.id))
        session2.desks.createDesk(label: "Work Desk", preset: .empty)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(
            makeIPCRequest(
                .deskList(target: .automatic),
                profileID: profile2.id.rawValue
            )
        )
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
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let profile2 = try #require(manager.createProfile(name: "Work", color: .blue))
        var openedProfileID: ProfileID?
        manager.openWindowAction = { route in
            openedProfileID = route.profileID
        }
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleRequest(makeIPCRequest(.openProfile(profileID: profile2.id.rawValue)))
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
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let route = ProfileWindowRoute(profileID: manager.personalProfileID)
        _ = try #require(manager.session(for: route))
        let window = TestWindow()
        manager.register(window: window, for: route)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(
            makeIPCRequest(.openProfile(profileID: manager.personalProfileID.rawValue))
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
                scriptSource: ""
            ),
            preferences: AppPreferences(defaults: makeTestDefaults(suiteName: suiteName)),
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let service = DenIPCService(profileManager: manager)
        let unknownUUID = UUID()

        // Act
        let response = await service.handleResult(
            makeIPCRequest(.openProfile(profileID: unknownUUID))
        )

        // Assert
        #expect(response.isOk == false)
        #expect(response.error?.contains("Profile not found") == true)
    }

    @Test func boardFocusSelectsSpecifiedBoardOnAnotherDesk() async throws {
        // Arrange
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "den-browser-ipc-board-focus-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        session.desks.createDesk(label: "Target", preset: .empty)
        let targetDeskID = session.navigation.presentedDeskID
        let boardID = try #require(session.boardOpening.createBoard(urlString: "https://example.com/", focus: false))
        _ = session.boardOpening.createBoard(urlString: "https://other.example/", focus: true)
        session.boardNavigation.focusDesk(sourceDeskID)
        let service = DenIPCService(profileManager: manager)

        // Act
        let response = await service.handleResult(makeIPCRequest(.focusBoard(boardID: boardID.rawValue)))

        // Assert
        #expect(response.isOk)
        #expect(session.navigation.presentedDeskID == targetDeskID)
        #expect(session.navigation.focusedBoard?.id == boardID)
    }
}
