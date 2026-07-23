import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStorePresentationTests {

    @Test func resetDenClearsRuntimePresentationAndPersistsFreshState() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [populated, empty], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        store.deleteFocusedDesk()
        store.toggleFocusedBoardMaximized()
        #expect(store.beginBoardDrag(board.id))

        store.resetDen()

        #expect(store.state.desks.count == 1)
        #expect(store.deskPendingDeletion == nil)
        #expect(store.maximizedBoardID == nil)
        #expect(!store.isBoardDragging)
        #expect(savedState == store.state)
    }

    @Test func resetDenRequiresConfirmationBeforeChangingState() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [populated], focusedDeskID: populated.id),
            onSave: { savedState = $0 })
        let originalState = store.state

        store.requestResetDenConfirmation()

        #expect(store.isResetDenPending)
        #expect(store.state == originalState)
        #expect(savedState == nil)

        store.cancelResetDen()

        #expect(!store.isResetDenPending)
        #expect(store.state == originalState)
        #expect(savedState == nil)
    }

    @Test func confirmingResetDenUsesExistingResetBehavior() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [populated], focusedDeskID: populated.id),
            onSave: { savedState = $0 })

        store.requestResetDenConfirmation()
        store.confirmResetDen()

        #expect(!store.isResetDenPending)
        #expect(store.state == .sample)
        #expect(savedState == store.state)
    }

    @Test func escapePassesThroughToSheetInput() throws {
        try withStore(desks: [desk("Desk")]) { store in
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

            #expect(!KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func escapeExitsDenMode() throws {
        try withStore(desks: [desk("Desk")]) { store in
            store.isDenMode = true
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

            #expect(KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func deskSwitchingExitsDenMode() {
        let first = desk("First")
        let second = desk("Second")
        let third = desk("Third")
        withStore(desks: [first, second, third]) { store in
            // 1. focusDesk(number:) exits DenMode on actual switch
            store.isDenMode = true
            store.focusDesk(number: 2)
            #expect(!store.isDenMode)
            #expect(store.focusedDesk?.id == second.id)

            // focusDesk(number:) on the same desk does NOT exit DenMode
            store.isDenMode = true
            store.focusDesk(number: 2)
            #expect(store.isDenMode)

            // 2. focusDesk(_:) exits DenMode on actual switch
            store.focusDesk(third.id)
            #expect(!store.isDenMode)
            #expect(store.focusedDesk?.id == third.id)

            // focusDesk(_:) on the same desk does NOT exit DenMode
            store.isDenMode = true
            store.focusDesk(third.id)
            #expect(store.isDenMode)

            // 3. focusPreviousDesk() / focusNextDesk() exits DenMode on actual switch
            store.isDenMode = true
            store.focusPreviousDesk()
            #expect(!store.isDenMode)
            #expect(store.focusedDesk?.id == second.id)

            store.isDenMode = true
            store.focusNextDesk()
            #expect(!store.isDenMode)
            #expect(store.focusedDesk?.id == third.id)

            // 4. enterOverviewSelection() exits DenMode on actual switch
            store.showOverview()
            store.isDenMode = true
            store.overviewSelectionDeskID = first.id
            store.enterOverviewSelection()
            #expect(!store.isDenMode)
            #expect(store.focusedDesk?.id == first.id)

            // enterOverviewSelection() on same desk does NOT exit DenMode
            store.showOverview()
            store.isDenMode = true
            store.overviewSelectionDeskID = first.id
            store.enterOverviewSelection()
            #expect(store.isDenMode)
        }
    }

    @Test func boardRenamingAndCustomLabelStickiness() {
        let b1 = board("Google", url: "https://google.com")
        withStore(desks: [desk("Main", boards: [b1])]) { store in
            // 1. Initially, customLabel is nil, displayName returns page title
            let boardID = b1.id
            guard
                let deskIndex = store.focusedDeskIndex,
                let boardIndex = store.focusedBoardIndex(in: deskIndex)
            else {
                Issue.record("Failed to find focused board indices")
                return
            }
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == nil)
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Google")

            // 2. Rename the board to a custom name
            store.renameFocusedBoard(to: "Search Tasks")
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == "Search Tasks")
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Search Tasks")
            #expect(!store.isDenMode)

            // 3. Navigation doesn't overwrite customLabel, but updates label
            store.updateBoard(
                boardID: boardID,
                url: URL(string: "https://google.com/search"),
                title: "Google Search Result"
            )
            // Original label is updated in the background
            #expect(store.state.desks[deskIndex].boards[boardIndex].label == "Google Search Result")
            // customLabel is untouched
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == "Search Tasks")
            // displayName still shows custom label
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Search Tasks")

            // 4. Duplicate the board (duplicate should copy customLabel)
            store.isDenMode = true
            store.duplicateFocusedBoard()
            let boards = store.focusedDesk?.boards ?? []
            #expect(boards.count == 2)
            #expect(boards[1].customLabel == "Search Tasks")
            #expect(boards[1].displayName == "Search Tasks")

            // 5. Focus original board and clear the label
            store.focusBoard(boardID)
            store.renameFocusedBoard(to: "")
            #expect(store.state.desks[deskIndex].boards[boardIndex].customLabel == nil)
            #expect(store.state.desks[deskIndex].boards[boardIndex].displayName == "Google Search Result")
        }
    }

    @Test func controlCommaTogglesDenMode() throws {
        try withStore(desks: [desk("Desk")]) { store in
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

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.isDenMode)
            #expect(KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func controlPeriodPassesThroughToSheetInput() throws {
        try withStore(desks: [desk("Desk")]) { store in
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

            #expect(!KeyboardController.handle(event, store: store))
            #expect(!store.isDenMode)
        }
    }

    @Test func commandOptionArrowsNavigateBoardsWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option])

            #expect(KeyboardController.handle(right, store: store))
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(!store.isDenMode)

            #expect(KeyboardController.handle(left, store: store))
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(!store.isDenMode)
        }
    }

    @Test func shiftCommandOptionArrowsMoveFocusedBoardWithoutEnteringDenMode() throws {
        let boards = [board("First"), board("Second")]
        try withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            let right = try arrowEvent(.rightArrow, modifiers: [.command, .option, .shift])
            let left = try arrowEvent(.leftArrow, modifiers: [.command, .option, .shift])

            #expect(KeyboardController.handle(right, store: store))
            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
            #expect(!store.isDenMode)

            #expect(KeyboardController.handle(left, store: store))
            #expect(store.focusedDesk?.boards.map(\.id) == boards.map(\.id))
            #expect(!store.isDenMode)
        }
    }

    @Test func commandQPassesThroughFromDenMode() throws {
        try withStore(desks: [desk("Desk")]) { store in
            store.isDenMode = true
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

            #expect(!KeyboardController.handle(event, store: store))
            #expect(store.isDenMode)
        }
    }

    @Test func denModeMaximizesAndCentersFocusedBoardWithoutChangingDenState() throws {
        let current = board("Current", width: 520)
        try withStore(desks: [desk("Desk", boards: [current])]) { store in
            store.isDenMode = true
            let stateBeforeCommands = store.state
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

            #expect(KeyboardController.handle(maximize, store: store))
            #expect(store.maximizedBoardID == current.id)
            let requestAfterMaximize = store.centerFocusedBoardRequest
            #expect(KeyboardController.handle(center, store: store))
            #expect(store.centerFocusedBoardRequest == requestAfterMaximize + 1)
            #expect(KeyboardController.handle(maximize, store: store))
            #expect(store.maximizedBoardID == nil)
            #expect(store.state == stateBeforeCommands)
        }
    }

    @Test func denModeBoardWidthPanelAdjustsAllBoardsAndAcceptsFitSelectionKeys() throws {
        let boards = [board("First"), board("Second")]
        try withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.isDenMode = true
            store.updateBoardLayout(availableWidth: 1_180, spacing: 10)
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

            #expect(KeyboardController.handle(open, store: store))
            #expect(store.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(ignoredMovement, store: store))
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(KeyboardController.handle(narrow, store: store))
            #expect(store.focusedDesk?.boards.map(\.width) == [440, 440])
            #expect(store.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(widen, store: store))
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 520])
            #expect(store.isBoardWidthPanelPresented)
            #expect(KeyboardController.handle(select, store: store))
            #expect(!store.isBoardWidthPanelPresented)
            #expect(store.isDenMode)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
        }
    }

    private func withStore(desks: [DeskState], body: (DenStore) throws -> Void) rethrows {
        let store = DenStore(state: DenState(desks: desks, focusedDeskID: desks[0].id))
        try body(store)
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

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
