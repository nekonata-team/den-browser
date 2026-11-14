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
struct WindowModeRoutingTests {
    @Test func boardRailSettingRemainsSharedAndObservable() {
        // Arrange
        withTestSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState()))
        ) { session in
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
        let target = makeTestBoard("Board")
        let source = makeTestDesk("Desk", boards: [target], focusedBoardID: target.id)
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
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

    @Test(arguments: [false, true])
    func escapeForwardsSheetInputOrExitsDenMode(inDenMode: Bool) throws {
        // Arrange
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [makeTestDesk("Desk")]))
            )
        ) { session, windowModel in
            windowModel.isDenMode = inDenMode
            let event = try keyEvent("\u{1B}", keyCode: 53)

            // Act
            let handled = KeyboardController.handle(event, session: session, windowModel: windowModel)

            // Assert
            #expect(handled == inDenMode)
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func directDeskSelectionExitsButRelativeNavigationKeepsDenMode() {
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second")
        let third = makeTestDesk("Third")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second, third]))
            )
        ) { session, windowModel in
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
        let googleBoard = makeTestBoard("Google", url: "https://google.com")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Main", boards: [googleBoard])])
                )
            )
        ) { session, windowModel in
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
                    session.resources.state.desks[deskOffset].boards[boardOffset].customLabel == "Search Tasks"
                )
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].displayName == "Search Tasks"
                )
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
                    session.resources.state.desks[deskOffset].boards[boardOffset].customLabel == "Search Tasks"
                )
                // displayName still shows custom label
                #expect(
                    session.resources.state.desks[deskOffset].boards[boardOffset].displayName == "Search Tasks"
                )

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
                        == "Google Search Result"
                )
                #expect(!session.resources.state.desks[deskOffset].boards[boardOffset].sheetNavigationPaused)
            })()
        }
    }

    @Test func controlCommaTogglesDenMode() throws {
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [makeTestDesk("Desk")]))
            )
        ) { session, windowModel in
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
                )
            )

            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(windowModel.isDenMode)
            #expect(KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func controlPeriodPassesThroughToSheetInput() throws {
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [makeTestDesk("Desk")]))
            )
        ) { session, windowModel in
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
                )
            )

            #expect(!KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(!windowModel.isDenMode)
        }
    }

    @Test func commandOptionArrowsNavigateBoardsWithoutEnteringDenMode() throws {
        let boards = [makeTestBoard("First"), makeTestBoard("Second")]
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)])
                )
            )
        ) { session, windowModel in
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
        let boards = [makeTestBoard("First"), makeTestBoard("Second")]
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)])
                )
            )
        ) { session, windowModel in
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
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [makeTestDesk("Desk")]))
            )
        ) { session, windowModel in
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
                )
            )

            #expect(!KeyboardController.handle(event, session: session, windowModel: windowModel))
            #expect(windowModel.isDenMode)
        }
    }

    @Test func denModeMaximizesAndCentersFocusedBoardWithoutChangingDenState() throws {
        let current = makeTestBoard("Current", width: 520)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: [current])])
                )
            )
        ) { session, windowModel in
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
                )
            )
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
                )
            )

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
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        let deskState = makeTestDesk("Desk", boards: [first, second], focusedBoardID: first.id)
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id)),
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
                keyCode: 3
            )
        )
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
                keyCode: 3
            )
        )

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
}
