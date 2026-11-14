import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import Observation
import Synchronization
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct WindowPanelPresentationTests {
    @Test func resetDenClearsRuntimePresentationAndPersistsFreshState() {
        // Arrange
        let board = makeTestBoard("Board")
        let populated = makeTestDesk("Populated", boards: [board])
        let empty = makeTestDesk("Empty")
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [populated, empty], focusedDeskID: populated.id)
                ),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
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
                board: board,
                sourceDeskID: populated.id,
                sourceBoardIndex: BoardIndex(rawValue: 0)
            )
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
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let focusedDesk = makeTestDesk("Desk", boards: [first, second], focusedBoardID: first.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [focusedDesk], focusedDeskID: focusedDesk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
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

    @Test func openBoardPanelRetainsDraftAndClearsOneShotStateAcrossTransitions() throws {
        let board = makeTestBoard("Insert After")
        let focusedDesk = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [focusedDesk],
                        focusedDeskID: focusedDesk.id
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
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
        let source = makeTestDesk("Desk")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            windowModel.showOpenBoardPanel()
            windowModel.openBoard.input = ":zmx project"

            // Act
            windowModel.openBoard.submit(preferredWidth: windowModel.defaultBoardWidth)

            // Assert
            #expect(windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.input == ":zmx project")
            #expect(
                windowModel.openBoard.message == "Set an absolute zmx executable path in Settings > Terminal."
            )
            #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func openBoardPanelOpensRecentItemAtRequestedPositionAndWidth() throws {
        // Arrange
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let source = makeTestDesk("Desk", boards: [first, second], focusedBoardID: second.id)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            let item = RecentItem.url(URL(string: "https://example.com/recent")!)
            windowModel.showOpenBoardPanel(afterBoardID: first.id)

            // Act
            windowModel.openBoard.submit(item.displayText, preferredWidth: 640)

            // Assert
            let opened = try #require(session.navigation.focusedBoard)
            #expect(opened.currentSheetURL == URL(string: item.displayText))
            #expect(opened.width == 640)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [first.id, opened.id, second.id]
            )
            #expect(session.resources.recentItems.first == item)
            #expect(!windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.message == nil)
        }
    }

    @Test(arguments: ["example.com", "Swift concurrency", "/tmp/drawer document.html"])
    func openBoardPanelOpensWebInputInDrawer(input: String) throws {
        // Arrange
        let first = makeTestBoard("First")
        let source = makeTestDesk("Desk", boards: [first], focusedBoardID: first.id)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            windowModel.showOpenBoardPanel(afterBoardID: first.id)
            windowModel.openBoard.input = input

            // Act
            windowModel.openBoard.submitToDrawer()

            // Assert
            let item = try #require(session.resources.state.drawerItems.first)
            let expected = BoardInputResolver.normalizedURL(
                from: input,
                searchEngine: session.configuration.preferences.searchEngine
            )
            #expect(WebURLPolicy.canonicalSheetURL(try #require(item.url)) == expected)
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [first.id])
            #expect(windowModel.isDrawerOpen)
            #expect(windowModel.drawer.expandedItemID == item.id)
            #expect(windowModel.openBoard.message == nil)
        }
    }

    @Test func confirmingResetDenUsesExistingResetBehavior() {
        let board = makeTestBoard("Board")
        let populated = makeTestDesk("Populated", boards: [board])
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [populated], focusedDeskID: populated.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
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

    @Test func denModeBoardWidthPanelAdjustsAllBoardsAndAcceptsFitSelectionKeys() throws {
        let boards = [makeTestBoard("First"), makeTestBoard("Second")]
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards)])
                )
            )
        ) { session, windowModel in
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
                )
            )
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
                )
            )
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
                )
            )
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
                )
            )

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
                } == true
            )
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
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
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
                )
        )

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
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
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
            configuration: makeTestBoardRuntimeConfiguration()
        )
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
        withTestSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState()))
        ) { session in
            do {
                let denWindowComposition = DenWindowComposition(session: session)
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
                    }
                )
                #expect(session.feedback.latest?.message == "Saved Essential 'Test'.")
                #expect(session.feedback.latest?.severity == .success)

                // Duplicate key waits for confirmation without changing preferences.
                windowModel.showSaveEssentialPanel(
                    name: "Another",
                    key: "t",
                    input: "https://another.com"
                )
                #expect(
                    windowModel.saveEssential(name: "Another", key: "t", input: "https://another.com")
                )
                #expect(windowModel.isSaveEssentialPanelPresented)
                #expect(windowModel.essentialPendingReplacement?.name == "Test")
                #expect(session.configuration.preferences.essentials.first?.name == "Test")
            }
        }
    }

    @Test func essentialReplacementDoesNotOverwriteReassignedKey() {
        withTestSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState()))
        ) { session in
            do {
                let denWindowComposition = DenWindowComposition(session: session)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                // Arrange
                #expect(
                    session.essentials.saveEssential(
                        name: "Original",
                        key: "e",
                        input: "https://example.com/original"
                    )
                )
                windowModel.showSaveEssentialPanel(
                    name: "Updated",
                    key: "e",
                    input: "https://example.com/updated"
                )
                #expect(
                    windowModel.saveEssential(
                        name: "Updated",
                        key: "e",
                        input: "https://example.com/updated"
                    )
                )
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
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [makeTestDesk("Empty")]))
            )
        ) { session, windowModel in
            windowModel.saveFocusedBoardAsEssential()
            #expect(!windowModel.isSaveEssentialPanelPresented)
            #expect(session.feedback.latest?.message == "No focused board.")
            #expect(session.feedback.latest?.severity == .warning)
        }
    }
}
