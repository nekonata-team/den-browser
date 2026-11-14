import AppKit
import DenApplication
import DenDomain
import DenInfrastructure
import DenModels
import DenViews
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct ProfileRuntimeSharingTests {
    @Test func extensionHostStaysUnloadedForEmptyAndTerminalStores() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [makeExtensionFixtureDescriptor()],
            uBOLiteEnabled: true
        )
        defer { manager.setUBOLiteEnabled(false) }
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        #expect(session.runtimes.webExtensionHost == nil)
        let terminal = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Terminal", boards: [terminal], focusedBoardID: terminal.id)
        session.resources.state = DenState(
            desks: [desk],
            focusedDeskID: desk.id
        )
        let window = NSWindow()
        let route = ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID)
        defer { manager.unregister(window: window, for: route) }

        // Act
        manager.register(window: window, for: route)
        manager.focusWebExtensionWindow(for: route)
        manager.setUBOLiteEnabled(false)
        manager.setUBOLiteEnabled(true)

        // Assert
        #expect(session.runtimes.webExtensionHost == nil)
        #expect(session.runtimes.webExtensionWindow == nil)
    }

    @Test func firstWebRuntimeLoadsOneSharedHostAcrossProfileWindows() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [makeExtensionFixtureDescriptor()]
        )
        defer { manager.setUBOLiteEnabled(false) }
        let profileID = manager.personalProfileID
        let firstRoute = ProfileWindowRoute(windowID: profileID.rawValue, profileID: profileID)
        let first = try #require(manager.session(for: firstRoute))
        manager.setUBOLiteEnabled(true)
        let sourceDeskID = first.navigation.presentedDeskID
        let boardID = try #require(
            first.boardOpening.createBoard(urlString: URL(fileURLWithPath: #filePath).absoluteString)
        )
        let board = try #require(first.resources.state.board(for: boardID))
        let firstRuntime = first.runtimes.webRuntime(for: board)
        first.desks.createDesk(label: "Second", preset: .empty)
        let secondRoute = try #require(
            manager.routeForOpeningDesk(
                sourceDeskID,
                profileID: profileID,
                sourceWindowID: firstRoute.windowID
            )
        )
        let second = try #require(manager.session(for: secondRoute))

        #expect(first.runtimes.webExtensionHost != nil)
        #expect(second.runtimes.webExtensionHost == nil)

        // Act
        let secondRuntime = second.runtimes.webRuntime(for: board)

        // Assert
        #expect(firstRuntime === secondRuntime)
        #expect(first.runtimes.webExtensionHost?.controller === second.runtimes.webExtensionHost?.controller)
        #expect(first.runtimes.webExtensionWindow !== second.runtimes.webExtensionWindow)
        #expect(first.runtimes.webExtensionWindow?.tabs.isEmpty == true)
        #expect(second.runtimes.webExtensionWindow?.tabs.count == 1)
    }

    @Test func drawerPeekRequestsHost() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [makeExtensionFixtureDescriptor()]
        )
        let profileID = manager.personalProfileID
        let session = try #require(manager.session(for: profileID))
        let fileURL = URL(fileURLWithPath: #filePath)
        let itemID = try #require(session.drawer.keepInDrawer(fileURL, opensDrawer: false))
        let item = try #require(session.resources.state.drawerItems.first { $0.id == itemID })
        manager.setUBOLiteEnabled(true)
        defer { manager.setUBOLiteEnabled(false) }

        // Act
        let firstPeek = session.drawer.drawerRuntime(for: item)

        // Assert
        #expect(session.runtimes.webExtensionHost != nil)
        #expect(session.runtimes.webExtensionWindow?.tabs.count == 1)
        #expect(firstPeek.id == item.id)
    }

    @Test func disablingExtensionDisconnectsLiveDrawerPeek() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [makeExtensionFixtureDescriptor()]
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let itemID = try #require(session.drawer.keepInDrawer(URL(fileURLWithPath: #filePath), opensDrawer: false))
        let item = try #require(session.resources.state.drawerItems.first { $0.id == itemID })
        manager.setUBOLiteEnabled(true)
        let peek = session.drawer.drawerRuntime(for: item)
        defer { manager.setUBOLiteEnabled(false) }

        // Act
        manager.setUBOLiteEnabled(false)

        // Assert
        #expect(session.windowResources.drawerPeek == nil)
        #expect(session.runtimes.webExtensionHost == nil)
        #expect(peek.webView.navigationDelegate == nil)
    }

    @Test func enablingExtensionAppliesToExistingWebRuntimeDemand() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(
            directory: directory,
            isEphemeral: true,
            webExtensionDescriptors: [makeExtensionFixtureDescriptor()]
        )
        let session = try #require(manager.session(for: manager.personalProfileID))
        let board = BoardState(label: "Web", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        session.resources.state = DenState(desks: [desk], focusedDeskID: desk.id)
        _ = session.runtimes.webRuntime(for: board)
        defer { manager.setUBOLiteEnabled(false) }
        #expect(session.runtimes.webExtensionHost == nil)

        // Act
        manager.setUBOLiteEnabled(true)
        _ = session.runtimes.webRuntime(for: board)

        // Assert
        #expect(session.runtimes.webExtensionHost != nil)
        #expect(session.runtimes.webExtensionWindow?.tabs.count == 1)
    }

    @Test func profileStoresUseSeparateWebKitStoresAndCallbacks() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "ProfileCallbackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        let navigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
        navigation.setEnabled(true)
        let manager = ProfileManager(
            directoryURL: directory,
            sheetNavigation: navigation,
            preferences: preferences,
            removeDataStore: { _ in },
            websiteDataStore: { _ in .nonPersistent() }
        )
        let second = try #require(manager.createProfile(name: "Second", color: .pink))
        let firstSession = try #require(manager.session(for: manager.personalProfileID))
        let secondSession = try #require(manager.session(for: second.id))
        let firstBoard = makeTestBoard("First")
        let secondBoard = makeTestBoard("Second")
        firstSession.resources.state = DenState(
            desks: [makeTestDesk("First", boards: [firstBoard])],
            focusedDeskID: DeskID()
        )
        firstSession.boardNavigation.focusDesk(firstSession.resources.state.desks[0].id)
        secondSession.resources.state = DenState(
            desks: [makeTestDesk("Second", boards: [secondBoard])],
            focusedDeskID: DeskID()
        )
        secondSession.boardNavigation.focusDesk(secondSession.resources.state.desks[0].id)
        let firstWebView = firstSession.runtimes.webRuntime(for: firstBoard).webView
        let secondWebView = secondSession.runtimes.webRuntime(for: secondBoard).webView

        // Act
        let firstHandled = navigation.handleScriptMessage(
            ["action": "openBoard", "url": "https://first.example/"],
            from: firstWebView
        )
        let secondHandled = navigation.handleScriptMessage(
            ["action": "openBoard", "url": "https://second.example/"],
            from: secondWebView
        )

        // Assert
        #expect(firstWebView.configuration.websiteDataStore !== secondWebView.configuration.websiteDataStore)
        #expect(firstHandled)
        #expect(secondHandled)
        #expect(
            firstSession.navigation.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://first.example/")
            } == true
        )
        #expect(
            secondSession.navigation.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://second.example/")
            } == true
        )
        #expect(
            firstSession.navigation.focusedDesk?.boards.contains {
                $0.currentSheetURL == URL(string: "https://second.example/")
            } == false
        )
    }

    @Test func multipleWindowsRetainSharedRuntimesWhenNonFinalWindowCloses() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let route1 = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        let window1 = NSWindow()
        let window2 = NSWindow()

        let session1 = try #require(manager.session(for: route1))
        manager.register(window: window1, for: route1)
        session1.desks.createDesk(label: "SecondDesk", preset: .empty)
        let secondDeskID = session1.navigation.presentedDeskID

        let route2 = try #require(
            manager.routeForOpeningDesk(
                secondDeskID,
                profileID: profileID,
                sourceWindowID: route1.windowID
            )
        )
        let session2 = try #require(manager.session(for: route2))
        manager.register(window: window2, for: route2)

        let targetBoard = makeTestBoard("SharedBoard")
        session1.resources.state = DenState(
            desks: [makeTestDesk("Main", boards: [targetBoard])],
            focusedDeskID: DeskID()
        )
        session1.boardNavigation.focusDesk(session1.resources.state.desks[0].id)
        let runtime = session1.runtimes.webRuntime(for: targetBoard)

        // Act
        manager.unregister(window: window1, for: route1)

        // Assert
        #expect(runtime.webView.navigationDelegate != nil)
        #expect(session2.resources.webRuntimes[targetBoard.id] === runtime)
    }

    @Test func sharedRuntimeDeliversEventsAfterItsOwnerWindowCloses() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let route1 = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        let window1 = NSWindow()
        let window2 = NSWindow()
        let targetBoard = BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
        weak var weakOwner: ProfileWindowSession?
        // Drain temporary AppKit bridge references while keeping the Profile and Runtime alive.
        let (runtime, storage, otherWindowSession, firstDeskID) = try autoreleasepool {
            var owner: ProfileWindowSession? = manager.session(for: route1)
            manager.register(window: window1, for: route1)
            let firstDeskID = try #require(owner?.navigation.presentedDeskID)
            owner?.desks.createDesk(label: "SecondDesk", preset: .empty)
            let secondDeskID = try #require(owner?.navigation.presentedDeskID)
            let route2 = try #require(
                manager.routeForOpeningDesk(
                    secondDeskID,
                    profileID: profileID,
                    sourceWindowID: route1.windowID
                )
            )
            let otherWindowSession = try #require(manager.session(for: route2))
            manager.register(window: window2, for: route2)

            let firstDeskIndex = try #require(owner?.resources.state.desks.firstIndex { $0.id == firstDeskID })
            owner?.resources.state.desks[firstDeskIndex].boards = [targetBoard]
            owner?.resources.state.desks[firstDeskIndex].focusedBoardID = targetBoard.id
            owner?.boardNavigation.focusDesk(firstDeskID)
            let runtime = try #require(owner?.runtimes.terminalRuntime(for: targetBoard))
            let storage = try #require(owner?.resources)

            weakOwner = owner
            var closedWindowEffects = 0
            owner?.connection.onWindowEffect = { _ in closedWindowEffects += 1 }

            // Act
            manager.unregister(window: window1, for: route1)
            let effectsAtClose = closedWindowEffects
            runtime.terminalDidRequestDesktopNotification(title: "After close", body: "Shared notification")
            runtime.terminalDidChangeFocus(true)
            #expect(closedWindowEffects == effectsAtClose)
            owner = nil
            return (runtime, storage, otherWindowSession, firstDeskID)
        }
        runtime.terminalDidChangeTitle("Updated after close")

        // Assert
        #expect(storage.state.desks.first { $0.id == firstDeskID }?.boards.first?.label == "Updated after close")
        #expect(otherWindowSession.resources === storage)
        #expect(weakOwner == nil)
        #expect(storage.notifications.contains { $0.boardID == targetBoard.id && $0.body == "Shared notification" })
    }

    @Test func retainedStorageAndRuntimeDoNotKeepStoreAliveAfterProfileManagerDeallocates() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var manager: ProfileManager? = makeTestProfileManager(directory: directory)
        let profileID = try #require(manager?.personalProfileID)
        let route = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        var session: ProfileWindowSession? = manager?.session(for: route)
        let targetBoard = makeTestBoard("TargetBoard")
        let targetDesk = makeTestDesk("Main", boards: [targetBoard])
        session?.resources.state = DenState(desks: [targetDesk], focusedDeskID: targetDesk.id)
        session?.boardNavigation.focusDesk(targetDesk.id)
        let runtime = try #require(session?.runtimes.webRuntime(for: targetBoard))
        let storage = try #require(session?.resources)
        weak let weakSession = session

        // Act
        session = nil
        manager = nil

        // Assert
        #expect(weakSession == nil)
        #expect(storage.webRuntimes[targetBoard.id] === runtime)
    }

    @Test func closingFinalWindowReleasesSharedRuntimes() throws {
        // Arrange
        let directory = makeTemporaryProfileDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = makeTestProfileManager(directory: directory)
        let profileID = manager.personalProfileID
        let route = ProfileWindowRoute(windowID: UUID(), profileID: profileID)
        let window = NSWindow()

        let session = try #require(manager.session(for: route))
        manager.register(window: window, for: route)

        let targetBoard = makeTestBoard("TargetBoard")
        session.resources.state = DenState(
            desks: [makeTestDesk("Main", boards: [targetBoard])],
            focusedDeskID: DeskID()
        )
        session.boardNavigation.focusDesk(session.resources.state.desks[0].id)
        let runtime = session.runtimes.webRuntime(for: targetBoard)

        weak let receiver = session.resources.boardRuntimes.receivers[targetBoard.id]

        // Act
        manager.unregister(window: window, for: route)

        // Assert
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(receiver == nil)
        #expect(session.resources.boardRuntimes.receivers.isEmpty)
    }
}
