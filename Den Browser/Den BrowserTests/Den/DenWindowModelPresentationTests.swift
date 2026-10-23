import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import DenViews
import Foundation
import Observation
import Synchronization
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenWindowModelPresentationTests {
    @Test func boardRailSettingRemainsSharedAndObservable() {
        // Arrange
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let first = DenWindowComposition(session: session).model
            let second = DenWindowComposition(session: session).model
            let isPresented = !first.isBoardRailPresented
            let changed = Mutex(false)
            withObservationTracking {
                _ = second.isBoardRailPresented
            } onChange: {
                changed.withLock { $0 = true }
            }

            // Act
            first.isBoardRailPresented = isPresented

            // Assert
            #expect(session.configuration.preferences.isBoardRailPresented == isPresented)
            #expect(first.isBoardRailPresented == isPresented)
            #expect(second.isBoardRailPresented == isPresented)
            #expect(changed.withLock { $0 })
        }
    }

    @Test func boardWidthKeepsSharedUpdatesObservable() {
        // Arrange
        let target = board("Board")
        let source = desk("Desk", boards: [target], focusedBoardID: target.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let changed = Mutex(false)
            withObservationTracking {
                _ = windowModel.defaultBoardWidth
            } onChange: {
                changed.withLock { $0 = true }
            }

            // Act
            session.resources.boardSizing.adjustBoard(target.id, by: 80)

            // Assert
            #expect(changed.withLock { $0 })
            #expect(windowModel.defaultBoardWidth == target.width + 80)
        }
    }

    @Test func resetDenClearsRuntimePresentationAndPersistsFreshState() {
        // Arrange
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [populated, empty], focusedDeskID: populated.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let runtime = session.runtimes.webRuntime(for: board)
        session.desks.deleteFocusedDesk()
        windowModel.maximizedBoardID = board.id
        windowModel.isBoardRailPresented = true
        #expect(session.boardNavigation.beginBoardDrag(board.id))
        session.resources.recentlyRemovedBoards = [
            RecentlyRemovedBoard(
                board: board, sourceDeskID: populated.id, sourceBoardIndex: BoardIndex(rawValue: 0))
        ]
        session.resources.recentlyDiscardedDrawerItems = [
            DrawerItem(url: URL(string: "https://discarded.example/")!)
        ]
        windowModel.setTemporaryContext(.zmxSessions)
        windowModel.openBoard.input = "unfinished search"
        windowModel.openBoard.afterBoardID = board.id
        session.navigation.previousFocusedDeskID = empty.id
        session.navigation.anchorJumpOriginBoardIDByDesk[populated.id] = board.id

        // Act
        session.reset.resetDen()

        // Assert
        #expect(session.resources.state.desks.count == 1)
        #expect(windowModel.pendingConfirmation == nil)
        #expect(windowModel.maximizedBoardID == nil)
        #expect(!windowModel.isFocusModePresented)
        #expect(!windowModel.isBoardRailPresented)
        #expect(!session.context.isBoardDragging)
        #expect(windowModel.temporaryContext == nil)
        #expect(savedState == session.resources.state)
        #expect(session.feedback.latest?.message == "Reset Den completed.")
        #expect(session.feedback.latest?.severity == .success)
        #expect(session.resources.webRuntimes.isEmpty)
        #expect(session.resources.recentlyRemovedBoards.isEmpty)
        #expect(session.resources.recentlyDiscardedDrawerItems.isEmpty)
        #expect(session.resources.notifications.isEmpty)
        #expect(windowModel.openBoard.input.isEmpty)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(session.navigation.previousFocusedDeskID == nil)
        #expect(session.navigation.anchorJumpOriginBoardIDByDesk.isEmpty)
        #expect(runtime.webView.navigationDelegate == nil)
        #expect(runtime.webView.uiDelegate == nil)
    }

    @Test func boardRailStaysOpenWhenFocusChangesAndPanelOpens() {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let focusedDesk = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        windowModel.toggleBoardRail()
        session.boardNavigation.focusBoard(second.id)
        windowModel.showOpenBoardPanel()

        // Assert
        #expect(session.navigation.focusedBoard?.id == second.id)
        #expect(windowModel.isOpenBoardPanelPresented)
        #expect(windowModel.isBoardRailPresented)
    }

    @Test func restoreRecentlyRemovedBoardReportsFeedbackWhenNoneExists() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        session.boardRemoval.restoreRecentlyRemovedBoard()
        #expect(session.feedback.latest?.message == "No removed board to restore.")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func invalidDeskNumberReportsFeedback() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        session.boardNavigation.focusDesk(number: 5)
        #expect(session.feedback.latest?.message == "Desk 5 does not exist.")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func reportFeedbackSetsLatestFeedbackWithSeverity() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        #expect(session.feedback.latest == nil)

        session.context.feedback.publish("Test Toast", severity: .warning)

        #expect(session.feedback.latest?.message == "Test Toast")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func reportFeedbackPreservesTitleAndBody() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())

        session.context.feedback.publish(title: "Build", body: "Finished")

        #expect(session.feedback.latest?.title == "Build")
        #expect(session.feedback.latest?.body == "Finished")
        #expect(session.feedback.latest?.message == "Build: Finished")
    }

    @Test func openBoardPanelRetainsDraftAndClearsOneShotStateAcrossTransitions() throws {
        let board = board("Insert After")
        let focusedDesk = desk("Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [focusedDesk],
                        focusedDeskID: focusedDesk.id))), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let url = try #require(URL(string: "https://example.com/current"))

        windowModel.showOpenBoardPanel()
        windowModel.openBoard.input = "unfinished search"
        windowModel.hideOpenBoardPanel()

        #expect(windowModel.openBoard.input == "unfinished search")
        #expect(windowModel.openBoard.afterBoardID == nil)

        windowModel.showOpenBoardPanel(initialURL: url, afterBoardID: board.id)
        windowModel.openBoard.message = "Try another input."

        #expect(windowModel.openBoard.input == url.absoluteString)
        #expect(windowModel.openBoard.afterBoardID == board.id)

        windowModel.showKeyboardShortcuts()

        #expect(windowModel.openBoard.input == url.absoluteString)
        #expect(windowModel.openBoard.initialURL == nil)
        #expect(windowModel.openBoard.afterBoardID == nil)
        #expect(windowModel.openBoard.message == nil)

        windowModel.hideKeyboardShortcuts()
        windowModel.showOpenBoardPanel()

        #expect(windowModel.openBoard.input == url.absoluteString)
        #expect(windowModel.openBoard.afterBoardID == nil)
    }

    @Test func openBoardPanelKeepsDraftAndShowsConfigurationFailure() {
        // Arrange
        let source = desk("Desk")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.showOpenBoardPanel()
            windowModel.openBoard.input = ":zmx project"

            // Act
            windowModel.openBoard.submit(preferredWidth: windowModel.defaultBoardWidth)

            // Assert
            #expect(windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.input == ":zmx project")
            #expect(
                windowModel.openBoard.message == "Set an absolute zmx executable path in Settings > Terminal.")
            #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func openBoardPanelOpensRecentItemAtRequestedPositionAndWidth() throws {
        // Arrange
        let first = board("First")
        let second = board("Second")
        let source = desk("Desk", boards: [first, second], focusedBoardID: second.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let item = RecentItem.url(URL(string: "https://example.com/recent")!)
            windowModel.showOpenBoardPanel(afterBoardID: first.id)

            // Act
            windowModel.openBoard.submit(item.displayText, preferredWidth: 640)

            // Assert
            let opened = try #require(session.navigation.focusedBoard)
            #expect(opened.currentSheetURL == URL(string: item.displayText))
            #expect(opened.width == 640)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [first.id, opened.id, second.id])
            #expect(session.resources.recentItems.first == item)
            #expect(!windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.message == nil)
        }
    }

    @Test(arguments: ["example.com", "Swift concurrency", "/tmp/drawer document.html"])
    func openBoardPanelOpensWebInputInDrawer(input: String) throws {
        // Arrange
        let first = board("First")
        let source = desk("Desk", boards: [first], focusedBoardID: first.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.showOpenBoardPanel(afterBoardID: first.id)
            windowModel.openBoard.input = input

            // Act
            windowModel.openBoard.submitToDrawer()

            // Assert
            let item = try #require(session.resources.state.drawerItems.first)
            let expected = BoardInputResolver.normalizedURL(
                from: input, searchEngine: session.configuration.preferences.searchEngine)
            #expect(WebURLPolicy.canonicalSheetURL(item.url) == expected)
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [first.id])
            #expect(windowModel.isDrawerOpen)
            #expect(windowModel.drawer.expandedItemID == item.id)
            #expect(windowModel.openBoard.message == nil)
        }
    }

    @Test(arguments: [":terminal", ":zellij project", ":zmx", ":tutorial", "https://", ""])
    func openBoardPanelKeepsInvalidDrawerInput(input: String) {
        // Arrange
        let source = desk("Desk")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.showOpenBoardPanel()
            windowModel.openBoard.input = input

            // Act
            windowModel.openBoard.submitToDrawer()

            // Assert
            #expect(windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.input == input)
            #expect(windowModel.openBoard.message != nil)
            #expect(session.resources.state.drawerItems.isEmpty)
            #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func openingBoardFeedbackTargetFocusesItsBoard() {
        let target = board("Target")
        let first = desk("First")
        let second = desk("Second", boards: [target])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.setTemporaryContext(.drawer)
        session.context.feedback.publish(title: "Build", body: "Finished", target: .board(target.id))
        session.notifications.openFeedbackTarget(session.feedback.latest?.target)

        #expect(session.navigation.presentedDeskID == second.id)
        #expect(session.navigation.focusedBoard?.id == target.id)
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func openingDrawerFeedbackTargetOpensAndExpandsItem() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let drawerDesk = desk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [drawerDesk],
                        focusedDeskID: drawerDesk.id,
                        drawerItems: [item]))), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.context.feedback.publish(
            title: nil,
            body: "Open item",
            target: DenFeedback.Target.drawerItem(item.id))
        session.notifications.openFeedbackTarget(session.feedback.latest?.target)

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.selectedItemID == item.id)
        #expect(windowModel.drawer.expandedItemID == item.id)
    }

    @Test func resetDenRequiresConfirmationBeforeChangingState() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [populated], focusedDeskID: populated.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let originalState = session.resources.state

        windowModel.requestResetDenConfirmation()

        #expect(windowModel.isResetDenPending)
        #expect(session.resources.state == originalState)
        #expect(savedState == nil)

        windowModel.cancelResetDen()

        #expect(!windowModel.isResetDenPending)
        #expect(session.resources.state == originalState)
        #expect(savedState == nil)
    }

    @Test func latestConfirmationReplacesEarlierRequestAndCanBeCancelled() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [populated, empty], focusedDeskID: populated.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.desks.deleteFocusedDesk()
        if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
            #expect(pending.id == populated.id)
        } else {
            Issue.record("Expected a desk deletion confirmation")
        }

        windowModel.requestResetDenConfirmation()
        #expect(windowModel.isResetDenPending)

        windowModel.cancelResetDen()
        #expect(!windowModel.hasPendingConfirmation)
    }

    @Test func confirmingResetDenUsesExistingResetBehavior() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [populated], focusedDeskID: populated.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.requestResetDenConfirmation()
        windowModel.confirmResetDen()

        #expect(!windowModel.isResetDenPending)
        #expect(session.resources.state.desks.count == 1)
        #expect(session.resources.state.desks.first?.label == "Main")
        #expect(session.resources.state.desks.first?.boards.isEmpty == true)
        #expect(session.resources.state.focusedDeskID == session.resources.state.desks.first?.id)
        #expect(savedState == session.resources.state)
    }

    @Test func escapePassesThroughToSheetInput() throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Desk")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "\u{1B}",
                    charactersIgnoringModifiers: "\u{1B}",
                    isARepeat: false,
                    keyCode: 53
                ))

            #expect(!KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func escapeExitsDenMode() throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Desk")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.isDenMode = true
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "\u{1B}",
                    charactersIgnoringModifiers: "\u{1B}",
                    isARepeat: false,
                    keyCode: 53
                ))

            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func directDeskSelectionExitsButRelativeNavigationKeepsDenMode() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second, third]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            // 1. focusDesk(number:) exits DenMode on actual switch
            windowModel.isDenMode = true
            session.boardNavigation.focusDesk(number: 2)
            #expect(!windowModel.isDenMode)
            #expect(session.navigation.focusedDesk?.id == second.id)

            // focusDesk(number:) exits even when the target is already focused
            windowModel.isDenMode = true
            session.boardNavigation.focusDesk(number: 2)
            #expect(!windowModel.isDenMode)

            // 2. focusDesk(_:) is direct selection
            session.boardNavigation.focusDesk(third.id)
            #expect(!windowModel.isDenMode)
            #expect(session.navigation.focusedDesk?.id == third.id)

            // focusDesk(_:) exits even when the target is already focused
            windowModel.isDenMode = true
            session.boardNavigation.focusDesk(third.id)
            #expect(!windowModel.isDenMode)

            // 3. Relative Desk Navigation keeps Den Mode active
            windowModel.isDenMode = true
            session.boardNavigation.focusPreviousDesk()
            #expect(windowModel.isDenMode)
            #expect(session.navigation.focusedDesk?.id == second.id)

            windowModel.isDenMode = true
            session.boardNavigation.focusNextDesk()
            #expect(windowModel.isDenMode)
            #expect(session.navigation.focusedDesk?.id == third.id)

            // 4. Overview confirmation exits even on the same Desk
            windowModel.showOverview()
            windowModel.isDenMode = true
            windowModel.overview.selectDesk(first.id)
            windowModel.overview.enterSelection()
            #expect(!windowModel.isDenMode)
            #expect(session.navigation.focusedDesk?.id == first.id)

            // Entering the selected Desk exits even when the target is already focused.
            windowModel.showOverview()
            windowModel.isDenMode = true
            windowModel.overview.selectDesk(first.id)
            windowModel.overview.enterSelection()
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func boardRenamingAndCustomLabelStickiness() {
        let googleBoard = board("Google", url: "https://google.com")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Main", boards: [googleBoard])]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            ({
                // 1. Initially, customLabel is nil, displayName returns page title
                let boardID = googleBoard.id
                guard
                    let deskIndex = session.context.focusedDeskIndex,
                    let boardIndex = session.boardNavigation.focusedBoardIndex(in: deskIndex)
                else {
                    Issue.record("Failed to find focused board indices")
                    return
                }
                let deskOffset = deskIndex.rawValue
                let boardOffset = boardIndex.rawValue
                #expect(session.resources.state.desks[deskOffset].boards[boardOffset].customLabel == nil)
                #expect(session.resources.state.desks[deskOffset].boards[boardOffset].displayName == "Google")

                // 2. Rename the board to a custom name
                session.boardOpening.renameFocusedBoard(to: "Search Tasks")
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].customLabel == "Search Tasks")
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].displayName == "Search Tasks")
                #expect(!windowModel.isDenMode)

                // 3. Navigation doesn't overwrite customLabel, but updates label
                session.runtimes.updateBoard(
                    boardID: boardID,
                    url: URL(string: "https://google.com/search"),
                    title: "Google Search Result"
                )
                // Original label is updated in the background
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].label == "Google Search Result"
                )
                // customLabel is untouched
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].customLabel == "Search Tasks")
                // displayName still shows custom label
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].displayName == "Search Tasks")

                // 4. Duplicate the board (duplicate should copy customLabel)
                session.boardNavigation.toggleBoardSheetNavigationPause(boardID)
                windowModel.isDenMode = true
                session.zmx.duplicateFocusedBoard()
                let boards = session.navigation.focusedDesk?.boards ?? []
                #expect(boards.count == 2)
                #expect(boards[1].customLabel == "Search Tasks")
                #expect(boards[1].displayName == "Search Tasks")
                #expect(boards[0].sheetNavigationPaused)
                #expect(boards[1].sheetNavigationPaused)

                // 5. Focus original board and clear the label
                session.boardNavigation.focusBoard(boardID)
                session.boardOpening.renameFocusedBoard(to: "")
                session.boardNavigation.toggleBoardSheetNavigationPause(boardID)
                #expect(session.resources.state.desks[deskOffset].boards[boardOffset].customLabel == nil)
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].displayName
                        == "Google Search Result")
                #expect(!session.resources.state.desks[deskOffset].boards[boardOffset].sheetNavigationPaused)
            })()
        }
    }

    @Test func controlCommaTogglesDenMode() throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Desk")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .control,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: ",",
                    charactersIgnoringModifiers: ",",
                    isARepeat: false,
                    keyCode: 43
                ))

            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(windowModel.isDenMode)
            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func controlPeriodPassesThroughToSheetInput() throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Desk")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .control,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: ".",
                    charactersIgnoringModifiers: ".",
                    isARepeat: false,
                    keyCode: 47
                ))

            #expect(!KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func commandOptionArrowsNavigateBoardsWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option])

            #expect(KeyboardController.handle(right, session: session, windowModel: windowModel))
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(!windowModel.isDenMode)

            #expect(KeyboardController.handle(left, session: session, windowModel: windowModel))
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func shiftCommandOptionArrowsMoveFocusedBoardWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option, .shift])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option, .shift])

            #expect(KeyboardController.handle(right, session: session, windowModel: windowModel))
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
            #expect(!windowModel.isDenMode)

            #expect(KeyboardController.handle(left, session: session, windowModel: windowModel))
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == boards.map(\.id))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func commandQPassesThroughFromDenMode() throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Desk")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.isDenMode = true
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "q",
                    charactersIgnoringModifiers: "q",
                    isARepeat: false,
                    keyCode: 12
                ))

            #expect(!KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(windowModel.isDenMode)
        }
    }

    @Test func denModeMaximizesAndCentersFocusedBoardWithoutChangingDenState() throws {
        let current = board("Current", width: 520)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: [current])]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.isDenMode = true
            let stateBeforeCommands = session.resources.state
            let maximize = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "f",
                    charactersIgnoringModifiers: "f",
                    isARepeat: false,
                    keyCode: 3
                ))
            let center = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "c",
                    charactersIgnoringModifiers: "c",
                    isARepeat: false,
                    keyCode: 8
                ))

            #expect(KeyboardController.handle(maximize, session: session, windowModel: windowModel))
            #expect(windowModel.maximizedBoardID == current.id)
            let requestAfterMaximize = windowModel.centerFocusedBoardRequest
            #expect(KeyboardController.handle(center, session: session, windowModel: windowModel))
            #expect(windowModel.centerFocusedBoardRequest == requestAfterMaximize + 1)
            #expect(KeyboardController.handle(maximize, session: session, windowModel: windowModel))
            #expect(windowModel.maximizedBoardID == nil)
            #expect(session.resources.state == stateBeforeCommands)
        }
    }

    @Test func focusModeIsRuntimeOnlyAndIgnoresKeyRepeat() throws {
        let first = board("First")
        let second = board("Second")
        let deskState = desk("Desk", boards: [first, second], focusedBoardID: first.id)
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }), configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let stateBeforeToggle = session.resources.state
        windowModel.isDenMode = true

        let toggle = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "F",
                charactersIgnoringModifiers: "f",
                isARepeat: false,
                keyCode: 3))
        let repeatedToggle = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "F",
                charactersIgnoringModifiers: "f",
                isARepeat: true,
                keyCode: 3))

        #expect(KeyboardController.handle(toggle, session: session, windowModel: windowModel))
        #expect(windowModel.isFocusModePresented)
        #expect(session.resources.state == stateBeforeToggle)
        #expect(savedState == nil)
        #expect(KeyboardController.handle(repeatedToggle, session: session, windowModel: windowModel))
        #expect(windowModel.isFocusModePresented)

        windowModel.exitDenMode()

        #expect(windowModel.isFocusModePresented)
        #expect(session.resources.state == stateBeforeToggle)
        #expect(savedState == nil)
    }

    @Test func denModeBoardWidthPanelAdjustsAllBoardsAndAcceptsFitSelectionKeys() throws {
        let boards = [board("First"), board("Second")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [desk("Desk", boards: boards)]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.isDenMode = true
            windowModel.updateBoardLayout(availableWidth: 1_180, spacing: 10)
            let open = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "w",
                    charactersIgnoringModifiers: "w",
                    isARepeat: false,
                    keyCode: 13
                ))
            let ignoredMovement = try arrowEvent(.rightArrow, modifiers: [])
            let narrow = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "-",
                    charactersIgnoringModifiers: "-",
                    isARepeat: false,
                    keyCode: 27
                ))
            let widen = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "=",
                    charactersIgnoringModifiers: "=",
                    isARepeat: false,
                    keyCode: 24
                ))
            let select = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "3",
                    charactersIgnoringModifiers: "3",
                    isARepeat: false,
                    keyCode: 20
                ))

            #expect(KeyboardController.handle(open, session: session, windowModel: windowModel))
            #expect(windowModel.isBoardWidthPanelPresented)
            #expect(
                KeyboardController.handle(ignoredMovement, session: session, windowModel: windowModel)
            )
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(KeyboardController.handle(narrow, session: session, windowModel: windowModel))
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [440, 440])
            #expect(windowModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(widen, session: session, windowModel: windowModel))
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [520, 520])
            #expect(windowModel.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(select, session: session, windowModel: windowModel))
            #expect(!windowModel.isBoardWidthPanelPresented)
            #expect(windowModel.isDenMode)
            #expect(
                session.navigation.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
        }
    }

    @Test func showSaveEssentialPanelForBoardPopulatesDraftAndSetsContext() {
        let board = BoardState(
            label: "Example Docs",
            width: 520,
            currentSheetURL: URL(string: "https://docs.example.com/api")
        )
        let desk = DeskState(label: "Work", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.showSaveEssentialPanel(for: board)

        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(
            windowModel.saveEssentialDraft
                == SaveEssentialDraft(
                    name: "Example Docs",
                    key: "",
                    input: "https://docs.example.com/api"
                ))

        windowModel.hideSaveEssentialPanel()
        #expect(!windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft == nil)
    }

    @Test func showSaveEssentialPanelForTerminalBoardPopulatesDraft() {
        let terminalBoard = BoardState(
            label: "Project Shell",
            width: 520,
            workingDirectory: "/Users/test/projects/demo"
        )
        let desk = DeskState(label: "Terminal", boards: [terminalBoard], focusedBoardID: terminalBoard.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.showSaveEssentialPanel(for: terminalBoard)

        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft?.name == "Project Shell")
        #expect(windowModel.saveEssentialDraft?.input == ":terminal /Users/test/projects/demo")
    }

    @Test func showSaveEssentialPanelForRecentItemPopulatesDraft() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let recent = RecentItem.url(URL(string: "https://github.com/apple/swift")!)

        windowModel.showSaveEssentialPanel(for: recent)

        #expect(windowModel.isSaveEssentialPanelPresented)
        #expect(windowModel.saveEssentialDraft?.name == "github.com")
        #expect(windowModel.saveEssentialDraft?.input == "https://github.com/apple/swift")
    }

    @Test func saveEssentialValidatesInputAndUpdatesPreferences() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            do {
                let denWindowSession = session
                let denWindowComposition = DenWindowComposition(session: denWindowSession)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                windowModel.showSaveEssentialPanel(name: "Test", key: "", input: "https://test.com")
                #expect(windowModel.isSaveEssentialPanelPresented)

                // Invalid: empty key
                #expect(!windowModel.saveEssential(name: "Test", key: "", input: "https://test.com"))
                #expect(windowModel.isSaveEssentialPanelPresented)

                // Invalid: multi-char key
                #expect(!windowModel.saveEssential(name: "Test", key: "ab", input: "https://test.com"))

                // Valid save
                #expect(windowModel.saveEssential(name: "Test", key: "t", input: "https://test.com"))
                #expect(!windowModel.isSaveEssentialPanelPresented)
                #expect(
                    session.configuration.preferences.essentials.contains {
                        $0.key == "t" && $0.name == "Test"
                    })
                #expect(session.feedback.latest?.message == "Saved Essential 'Test'.")
                #expect(session.feedback.latest?.severity == .success)

                // Duplicate key waits for confirmation without changing preferences.
                windowModel.showSaveEssentialPanel(
                    name: "Another", key: "t", input: "https://another.com")
                #expect(
                    windowModel.saveEssential(name: "Another", key: "t", input: "https://another.com"))
                #expect(windowModel.isSaveEssentialPanelPresented)
                #expect(windowModel.essentialPendingReplacement?.name == "Test")
                #expect(session.configuration.preferences.essentials.first?.name == "Test")
            }
        }
    }

    @Test(arguments: [false, true])
    func essentialReplacementRequiresConfirmationAndPreservesIdentity(confirm: Bool) throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            do {
                let denWindowSession = session
                let denWindowComposition = DenWindowComposition(session: denWindowSession)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                // Arrange
                #expect(
                    session.essentials.saveEssential(
                        name: "Original", key: "e", input: "https://example.com/original"))
                #expect(
                    session.essentials.saveEssential(
                        name: "Other", key: "E", input: "https://example.com/other"))
                let original = session.configuration.preferences.essentials
                let draft = SaveEssentialDraft(
                    name: "Updated", key: "e", input: "https://example.com/updated")
                windowModel.showSaveEssentialPanel(
                    name: draft.name, key: draft.key, input: draft.input)
                #expect(
                    windowModel.saveEssential(
                        name: draft.name, key: draft.key, input: draft.input))

                // Act
                if confirm {
                    windowModel.confirmEssentialReplacement()
                } else {
                    windowModel.cancelEssentialReplacement()
                }

                // Assert
                #expect(windowModel.pendingConfirmation == nil)
                #expect(windowModel.isSaveEssentialPanelPresented == !confirm)
                #expect(
                    session.configuration.preferences.essentials.map(\.id)
                        == original.map(\.id))
                #expect(session.configuration.preferences.essentials.last == original.last)
                if confirm {
                    let replaced = try #require(
                        session.configuration.preferences.essentials.first)
                    #expect(replaced.name == draft.name)
                    #expect(replaced.key == draft.key)
                    #expect(replaced.input == draft.input)
                } else {
                    #expect(session.configuration.preferences.essentials == original)
                    #expect(windowModel.saveEssentialDraft == draft)
                }
            }
        }
    }

    @Test func essentialReplacementDoesNotOverwriteReassignedKey() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            do {
                let denWindowSession = session
                let denWindowComposition = DenWindowComposition(session: denWindowSession)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                // Arrange
                #expect(
                    session.essentials.saveEssential(
                        name: "Original", key: "e", input: "https://example.com/original"))
                windowModel.showSaveEssentialPanel(
                    name: "Updated", key: "e", input: "https://example.com/updated")
                #expect(
                    windowModel.saveEssential(
                        name: "Updated", key: "e", input: "https://example.com/updated"))
                let other = Essential(name: "Other", key: "e", input: "https://example.com/other")
                #expect(session.configuration.preferences.setEssentials([other]))

                // Act
                windowModel.confirmEssentialReplacement()

                // Assert
                #expect(session.configuration.preferences.essentials == [other])
                #expect(windowModel.isSaveEssentialPanelPresented)
                #expect(windowModel.essentialPendingReplacement != nil)
                #expect(session.feedback.latest?.severity == .warning)
            }
        }
    }

    @Test func saveFocusedBoardAsEssentialShowsToastWhenNoBoardFocused() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk("Empty")]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            windowModel.saveFocusedBoardAsEssential()
            #expect(!windowModel.isSaveEssentialPanelPresented)
            #expect(session.feedback.latest?.message == "No focused board.")
            #expect(session.feedback.latest?.severity == .warning)
        }
    }

    @Test func openFeedbackTargetCentersBoardEvenWhenAlreadyFocused() {
        let targetBoard = board("Target")
        var currentDesk = desk("Main", boards: [targetBoard], focusedBoardID: targetBoard.id)
        currentDesk.scrollOffsetX = 180
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [currentDesk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let windowModel = denWindowComposition.model
            let session = denWindowSession

            let initialCenterRequests = windowModel.centerFocusedBoardRequest

            // Act
            session.notifications.openFeedbackTarget(.board(targetBoard.id))

            // Assert
            #expect(windowModel.centerFocusedBoardRequest == initialCenterRequests + 1)
            #expect(session.navigation.focusedDesk?.scrollOffsetX == nil)
        }
    }

    @Test func openFeedbackTargetDoesNotScrollWindowWhenTargetIsPresentedElsewhere() {
        let sourceBoard = board("Source")
        let targetBoard = board("Target")
        var sourceDesk = desk("Source", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        sourceDesk.scrollOffsetX = 180
        let targetDesk = desk("Target", boards: [targetBoard], focusedBoardID: targetBoard.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [sourceDesk, targetDesk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let existingSession = denWindowSession

            let session = ProfileWindowSession(
                resources: existingSession.resources,
                configuration: makeTestBoardRuntimeConfiguration(
                    websiteDataStore: .nonPersistent(),
                    sheetNavigation: existingSession.configuration.sheetNavigation,
                    preferences: existingSession.configuration.preferences), presentedDeskID: sourceDesk.id,
                canPresentDesk: { _ in false }, onDeskPresentationRequest: { _ in false }, onWillResetDen: {})

            session.notifications.openFeedbackTarget(.board(targetBoard.id))

            #expect(session.navigation.presentedDeskID == sourceDesk.id)
            #expect(session.navigation.focusedDesk?.scrollOffsetX == 180)
        }
    }

    private func arrowEvent(
        _ specialKey: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        let (characters, keyCode): (String, UInt16) =
            switch specialKey {
            case .leftArrow: ("\u{F702}", 123)
            case .rightArrow: ("\u{F703}", 124)
            default: ("", 0)
            }
        return try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
