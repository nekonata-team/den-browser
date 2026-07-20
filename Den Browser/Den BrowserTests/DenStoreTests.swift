import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStoreTests {
    @Test func openBoardAcceptsWebHostsAndSearchesInvalidURLs() throws {
        let source = desk("Desk")
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.addBoard(urlString: "localhost:3000")
        let localURL = try #require(store.focusedDesk?.boards.last?.currentSheetURL)
        #expect(localURL.scheme == "https")
        #expect(localURL.host == "localhost")
        #expect(localURL.port == 3000)

        store.addBoard(urlString: "swift: concurrency")
        let searchURL = try #require(
            store.focusedDesk?.boards.last?.currentSheetURL
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(searchURL.host == "www.google.com")
        #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "swift: concurrency")])

        store.addBoard(urlString: "https://")
        let invalidURLSearch = try #require(
            store.focusedDesk?.boards.last?.currentSheetURL
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(invalidURLSearch.queryItems == [URLQueryItem(name: "q", value: "https://")])
    }

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

    @Test func emptyPersistedDenRecoversAndSavesOneDesk() {
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [], focusedDeskID: UUID()),
            onSave: { savedState = $0 })

        #expect(store.state.desks.count == 1)
        #expect(store.focusedDesk != nil)
        #expect(savedState == store.state)
    }

    @Test func createsEmptyDeskAfterFocusedDesk() {
        withStore(desks: [desk("First"), desk("Second")]) { store in
            store.createDesk(label: "  Writing  ", preset: .empty)

            #expect(store.state.desks.map(\.label) == ["First", "Writing", "Second"])
            #expect(store.focusedDesk?.label == "Writing")
            #expect(store.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func createsChatGPTPresetWithThreeBoards() {
        withStore(desks: [desk("First")]) { store in
            store.createDesk(label: "AI", preset: .chatGPT)

            #expect(store.focusedDesk?.boards.count == 3)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://chatgpt.com/")
                } == true)
            #expect(store.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
            #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.first?.id)
        }
    }

    @Test func createsGeminiPresetWithThreeBoards() {
        withStore(desks: [desk("First")]) { store in
            store.createDesk(label: "Gemini", preset: .gemini)

            #expect(store.focusedDesk?.boards.count == 3)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    $0.currentSheetURL == URL(string: "https://gemini.google.com/") && $0.width == 520
                } == true)
        }
    }

    @Test func deskPresetSearchRanksFuzzyLabelsBeforeBoardAndHostMatches() throws {
        let boards = [
            DeskPresetBoard(
                label: "Gemini Research",
                width: 520,
                initialSheetURL: URL(string: "https://docs.google.com/"))
        ]

        let labelScore = try #require(
            DeskPresetSearch.score(query: "chat", label: "ChatGPT", boards: []))
        let boardScore = try #require(
            DeskPresetSearch.score(query: "gemres", label: "Research", boards: boards))
        let hostScore = try #require(
            DeskPresetSearch.score(query: "docs", label: "Research", boards: boards))

        #expect(labelScore < boardScore)
        #expect(boardScore < hostScore)
        #expect(DeskPresetSearch.score(query: "claude", label: "Research", boards: boards) == nil)
    }

    @Test func personalPresetCapturesStableBoardStateAndCreatesIndependentDesk() throws {
        let first = board("Mail", width: 420, url: "https://mail.example.com/inbox?label=work#today")
        let second = board("Notes", width: 760, url: "")
        let source = desk("Morning", boards: [first, second], focusedBoardID: second.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        #expect(store.saveFocusedDeskAsPreset(label: "  Morning  ") == .created)
        let preset = try #require(store.deskPresets.first)
        #expect(preset.label == "Morning")
        #expect(preset.boards.map(\.label) == ["Mail", "Notes"])
        #expect(preset.boards.map(\.width) == [420, 760])
        #expect(
            preset.boards[0].initialSheetURL
                == URL(string: "https://mail.example.com/inbox?label=work#today"))
        #expect(preset.boards[1].initialSheetURL == nil)
        #expect(preset.focusedBoardIndex == 1)

        store.createDesk(label: "Copy", personalPresetID: preset.id)
        let copy = try #require(store.focusedDesk)
        #expect(copy.boards.map(\.id) != source.boards.map(\.id))
        #expect(copy.boards.map(\.label) == source.boards.map(\.label))
        #expect(copy.focusedBoardID == copy.boards[1].id)
    }

    @Test func personalPresetValidationReplacementAndDeletion() throws {
        let source = desk("Desk", boards: [board("First")])
        var saves: [[PersonalDeskPreset]] = []
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            deskPresets: [],
            onDeskPresetsSave: { saves.append($0) })

        #expect(store.saveFocusedDeskAsPreset(label: "Empty") == .reservedLabel)
        #expect(store.saveFocusedDeskAsPreset(label: "ChatGPT") == .reservedLabel)
        #expect(store.saveFocusedDeskAsPreset(label: "Routine") == .created)
        #expect(store.saveFocusedDeskAsPreset(label: "Other") == .created)
        #expect(store.deskPresets.map(\.label) == ["Other", "Routine"])

        let routineID = try #require(store.deskPresets.last?.id)
        store.state.desks[0].boards[0].width = 900
        #expect(store.saveFocusedDeskAsPreset(label: " routine ") == .replacementPending)
        #expect(store.deskPresets.last?.boards[0].width == 520)
        store.confirmDeskPresetReplacement()
        #expect(store.deskPresets.last?.id == routineID)
        #expect(store.deskPresets.last?.boards[0].width == 900)

        store.requestDeskPresetDeletion(routineID)
        store.confirmDeskPresetDeletion()
        #expect(store.deskPresets.map(\.label) == ["Other"])
        #expect(saves.count == 4)
    }

    @Test func emptyDeskCannotBecomePersonalPreset() {
        withStore(desks: [desk("Empty")]) { store in
            #expect(store.saveFocusedDeskAsPreset(label: "Saved") == .emptyDesk)
            #expect(store.deskPresets.isEmpty)
            store.showSaveDeskPresetPanel()
            #expect(!store.isSaveDeskPresetPanelPresented)
        }
    }

    @Test func boardFocusMovesAndWrapsAtBothEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.focusNextBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)

            store.focusPreviousBoard()
            store.focusPreviousBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[2].id)

            store.focusNextBoard()
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func focusingAlreadyFocusedBoardDoesNotSaveAgain() {
        let board = board("Focused")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) { _ in
            saveCount += 1
        }

        store.focusBoard(board.id)

        #expect(saveCount == 0)
    }

    @Test func boardMovementAvailabilityStopsAtDeskEdges() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            #expect(!store.canMoveBoard(boards[0].id, by: -1))
            #expect(store.canMoveBoard(boards[0].id, by: 1))
            #expect(store.canMoveBoard(boards[1].id, by: -1))
            #expect(store.canMoveBoard(boards[1].id, by: 1))
            #expect(store.canMoveBoard(boards[2].id, by: -1))
            #expect(!store.canMoveBoard(boards[2].id, by: 1))
        }
    }

    @Test func reorderingBoardKeepsItFocusedAndStopsAtDeskEdge() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.moveFocusedBoardLeft()
            store.moveFocusedBoardLeft()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(store.centerFocusedBoardRequest == 1)
        }
    }

    @Test func boardDragPersistsOnlyItsFinalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var savedStates: [DenState] = []
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            savedStates.append($0)
        }

        #expect(store.beginBoardDrag(boards[0].id))
        store.previewBoardMove(boards[0].id, to: 2)
        #expect(savedStates.isEmpty)

        store.finishBoardDrag()
        #expect(savedStates.count == 1)
        #expect(savedStates[0].desks[0].boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
    }

    @Test func cancelledBoardDragRestoresAndPersistsOriginalOrder() {
        let boards = [board("A"), board("B"), board("C")]
        let source = desk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        #expect(store.beginBoardDrag(boards[0].id))
        store.previewBoardMove(boards[0].id, to: 2)
        store.restoreBoardOrder(boards.map(\.id), in: source.id)
        store.finishBoardDrag()

        #expect(store.focusedDesk?.boards.map(\.id) == boards.map(\.id))
        #expect(persistedState?.desks[0].boards.map(\.id) == boards.map(\.id))
    }

    @Test func movingBoardToDeskPlacesItAfterTargetAndFocusesIt() {
        let moved = board("Moved")
        let targetBoards = [board("Before"), board("Target"), board("After")]
        let source = desk("Source", boards: [moved])
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withStore(desks: [source, target]) { store in
            store.moveFocusedBoardToNextDesk()

            #expect(store.state.desks[0].boards.isEmpty)
            #expect(store.state.desks[0].focusedBoardID == nil)
            #expect(
                store.state.desks[1].boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, moved.id, targetBoards[2].id,
                ])
            #expect(store.focusedDesk?.id == target.id)
            #expect(store.focusedDesk?.focusedBoardID == moved.id)
        }
    }

    @Test func removingBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(store.recentlyRemovedBoard?.board.id == boards[1].id)
        }
    }

    @Test func removingFirstBoardFocusesNextBoard() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[0].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removingLastBoardFocusesPreviousBoard() {
        let boards = [board("A"), board("B")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeFocusedBoard()

            #expect(store.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func removingUnfocusedBoardKeepsFocus() {
        let boards = [board("A"), board("B"), board("C")]
        withStore(desks: [desk("Desk", boards: boards, focusedBoardID: boards[1].id)]) { store in
            store.removeBoard(boards[0].id)

            #expect(store.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id])
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
        }
    }

    @Test func removalReplacesRestoreCandidateAndDoesNotPersistIt() throws {
        let boards = [board("First"), board("Second")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id)) {
            persistedState = $0
        }

        store.removeFocusedBoard()
        store.removeFocusedBoard()
        let persisted = try #require(persistedState)

        #expect(store.recentlyRemovedBoard?.board.id == boards[1].id)
        #expect(persisted.desks[0].boards.isEmpty)
        #expect(DenStore(state: persisted).recentlyRemovedBoard == nil)
    }

    @Test func restorationUsesOriginalDeskIndexAndBoardIdentity() {
        let boards = [board("First"), board("Restored", width: 760), board("Last")]
        let source = desk("Source", boards: boards, focusedBoardID: boards[1].id)
        withStore(desks: [source]) { store in
            store.removeFocusedBoard()
            store.restoreRecentlyRemovedBoard()

            #expect(store.focusedDesk?.boards == boards)
            #expect(store.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(store.recentlyRemovedBoard == nil)
        }
    }

    @Test func restorationCreatesANewBoardRuntime() throws {
        let removed = board("Removed")
        try withStore(desks: [desk("Desk", boards: [removed])]) { store in
            let originalRuntime = store.runtime(for: removed)

            store.removeFocusedBoard()
            #expect(store.runtimes[removed.id] == nil)

            store.restoreRecentlyRemovedBoard()
            let restoredBoard = try #require(store.focusedDesk?.boards.first)
            let restoredRuntime = store.runtime(for: restoredBoard)
            #expect(restoredRuntime !== originalRuntime)
        }
    }

    @Test func restorationFallsBackRightOfFocusedBoardWhenSourceDeskIsGone() {
        let removed = board("Removed")
        let source = desk("Source", boards: [removed])
        let targetBoards = [board("Before"), board("Focused"), board("After")]
        let target = desk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withStore(desks: [source, target]) { store in
            store.removeFocusedBoard()
            store.deleteFocusedDesk()
            store.restoreRecentlyRemovedBoard()

            #expect(store.focusedDesk?.id == target.id)
            #expect(
                store.focusedDesk?.boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, removed.id, targetBoards[2].id,
                ])
            #expect(store.focusedDesk?.focusedBoardID == removed.id)
        }
    }

    @Test func deskCreationStopsAtTenDesks() {
        let desks = (1...DenStore.maximumDeskCount).map { desk("Desk \($0)") }
        withStore(desks: desks) { store in
            store.createDesk(label: "Overflow", preset: .empty)

            #expect(store.state.desks.count == DenStore.maximumDeskCount)
            #expect(!store.canCreateDesk)
        }
    }

    @Test func deletingEmptyDeskFocusesDeskThatTakesItsPosition() {
        let first = desk("First")
        let empty = desk("Empty")
        let third = desk("Third")
        withStore(desks: [first, empty, third]) { store in
            store.focusDesk(empty.id)
            store.deleteFocusedDesk()

            #expect(store.state.desks.map(\.id) == [first.id, third.id])
            #expect(store.focusedDesk?.id == third.id)
        }
    }

    @Test func deletingDeskWithBoardsRequiresConfirmation() {
        let board = board("Board")
        let populated = desk("Populated", boards: [board])
        let empty = desk("Empty")
        withStore(desks: [populated, empty]) { store in
            store.deleteFocusedDesk()

            #expect(store.state.desks.count == 2)
            #expect(store.deskPendingDeletion?.id == populated.id)

            store.focusDesk(empty.id)
            store.confirmDeskDeletion()
            #expect(store.state.desks.map(\.id) == [empty.id])
            #expect(store.focusedDesk?.id == empty.id)
            #expect(store.deskPendingDeletion == nil)
        }
    }

    @Test func cancellingDeskDeletionKeepsBoards() {
        let populated = desk("Populated", boards: [board("Board")])
        let empty = desk("Empty")
        withStore(desks: [populated, empty]) { store in
            store.deleteFocusedDesk()
            store.cancelDeskDeletion()

            #expect(store.state.desks.map(\.id) == [populated.id, empty.id])
            #expect(store.deskPendingDeletion == nil)
        }
    }

    @Test func lastDeskCannotBeDeleted() {
        let onlyDesk = desk("Only")
        withStore(desks: [onlyDesk]) { store in
            store.deleteFocusedDesk()

            #expect(store.state.desks.count == 1)
            #expect(store.deskPendingDeletion == nil)
        }
    }

    @Test func digitDeskMovementFocusesAndMovesToNumberedDesk() {
        let moving = board("Moving")
        let targetBoard = board("Target")
        let source = desk("One", boards: [moving])
        let target = desk("Two", boards: [targetBoard])
        withStore(desks: [source, target]) { store in
            store.moveFocusedBoard(toDeskNumber: 2)

            #expect(store.focusedDesk?.id == target.id)
            #expect(store.state.desks[1].boards.map(\.id) == [targetBoard.id, moving.id])

            store.focusDesk(number: 1)
            #expect(store.focusedDesk?.id == source.id)
        }
    }

    @Test func persistedStateRestoresDeskAndBoardDataAndFocus() throws {
        let firstBoards = [
            board("One", width: 440, url: "https://one.example/path"),
            board("Two", width: 760, url: "https://two.example/"),
        ]
        let secondBoards = [board("Three", width: 980, url: "https://three.example/query?q=1")]
        let first = desk("First", boards: firstBoards, focusedBoardID: firstBoards[1].id)
        let second = desk("Second", boards: secondBoards, focusedBoardID: secondBoards[0].id)
        var persistedState: DenState?
        let writer = DenStore(state: DenState(desks: [first, second], focusedDeskID: second.id)) {
            persistedState = $0
        }

        writer.focusDesk(first.id)
        let restored = try #require(persistedState)

        #expect(restored == writer.state)
        #expect(restored.desks.map(\.id) == [first.id, second.id])
        #expect(restored.desks[0].boards.map(\.id) == firstBoards.map(\.id))
        #expect(restored.desks.map(\.label) == ["First", "Second"])
        #expect(restored.desks[0].boards.map(\.label) == ["One", "Two"])
        #expect(restored.desks[0].boards.map(\.width) == [440, 760])
        #expect(
            restored.desks[0].boards.map(\.currentSheetURL) == [
                URL(string: "https://one.example/path"), URL(string: "https://two.example/"),
            ])
        #expect(restored.focusedDeskID == first.id)
        #expect(restored.desks.map(\.focusedBoardID) == [firstBoards[1].id, secondBoards[0].id])
    }

    @Test func mouseResizeChangesTargetBoardWidthWithinBounds() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.resizeBoard(boards[1].id, to: 760)
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 760])

            store.resizeBoard(boards[1].id, to: 100)
            #expect(store.focusedDesk?.boards[1].width == 280)

            store.resizeBoard(boards[1].id, to: 2_000)
            #expect(store.focusedDesk?.boards[1].width == 1400)
        }
    }

    @Test func resizesEveryBoardInFocusedDeskToFitCurrentWindow() {
        let firstBoards = [board("First", width: 440), board("Second", width: 760)]
        let otherBoard = board("Other", width: 980)
        let firstDesk = desk("First", boards: firstBoards, focusedBoardID: firstBoards[0].id)
        let secondDesk = desk("Second", boards: [otherBoard])
        withStore(desks: [firstDesk, secondDesk]) { store in
            store.updateBoardLayout(availableWidth: 1_180, spacing: 10)
            store.toggleFocusedBoardMaximized()
            let centerRequest = store.centerFocusedBoardRequest

            #expect(store.resizeFocusedDeskBoards(toFit: 3))
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
            #expect(store.state.desks[1].boards[0].width == 980)
            #expect(store.maximizedBoardID == nil)
            #expect(store.centerFocusedBoardRequest == centerRequest + 1)
        }
    }

    @Test func rejectsBoardFitCountsOutsideCurrentWidth() {
        let boards = [board("First"), board("Second")]
        withStore(desks: [desk("Desk", boards: boards)]) { store in
            store.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(store.boardWidth(toFit: 3) != nil)
            #expect(store.boardWidth(toFit: 4) == nil)
            #expect(!store.resizeFocusedDeskBoards(toFit: 4))
            #expect(store.focusedDesk?.boards.map(\.width) == [520, 520])
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        withStore(desks: [desk("Desk", boards: [board("Wide")])]) { store in
            store.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(store.resizeFocusedDeskBoards(toFit: 1))
            #expect(store.focusedDesk?.boards[0].width == 2_480)
        }
    }

    @Test func commandTOpensBoardPanelFromOverview() throws {
        try withStore(desks: [desk("Desk")]) { store in
            store.showOverview()
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "t",
                    charactersIgnoringModifiers: "t",
                    isARepeat: false,
                    keyCode: 17
                ))

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.isOpenBoardPanelPresented)
            #expect(!store.isOverviewPresented)
        }
    }

    @Test func temporaryContextsAreExclusiveAndClearOverviewSelection() {
        let board = board("Board")
        withStore(desks: [desk("Desk", boards: [board], focusedBoardID: board.id)]) { store in
            store.showOverview()
            #expect(store.temporaryContext == .overview)
            #expect(store.overviewSelectionBoardID == board.id)

            store.showOpenBoardPanel()

            #expect(store.temporaryContext == .openBoard)
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)
            #expect(!store.isOverviewPresented)
        }
    }

    @Test func overviewFilteringAndNavigation() {
        let b1 = board("Google", url: "https://google.com")
        let b2 = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [b1], focusedBoardID: b1.id)
        let desk2 = desk("Dev", boards: [b2], focusedBoardID: b2.id)

        withStore(desks: [desk1, desk2]) { store in
            // 1. Show overview
            store.showOverview()
            #expect(store.overviewQuery == "")
            #expect(!store.isOverviewFilterMode)
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == b1.id)

            // 2. Set query matching b2
            store.setOverviewQuery("git")
            #expect(store.overviewQuery == "git")
            // Selection should jump to first matching board (b2 in desk2)
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == b2.id)

            // 3. Re-set query matching b1
            store.setOverviewQuery("oog")
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == b1.id)

            // 4. Test matchesOverviewFilter
            #expect(store.matchesOverviewFilter(b1, in: desk1))
            #expect(!store.matchesOverviewFilter(b2, in: desk2))

            // 5. Non-matching query clears selection
            store.setOverviewQuery("nonexistent")
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)

            // 6. Enter filter mode, type query, and confirm it
            store.enterOverviewFilterMode()
            #expect(store.isOverviewFilterMode)
            store.setOverviewQuery("git")
            store.confirmOverviewFilterQuery()
            #expect(!store.isOverviewFilterMode)
            #expect(store.overviewQuery == "git")

            // 7. Clear query in normal mode
            store.clearOverviewQuery()
            #expect(store.overviewQuery == "")
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == b2.id)

            // 8. Escape clears filter mode and query
            store.enterOverviewFilterMode()
            store.exitOverviewFilterMode()
            #expect(!store.isOverviewFilterMode)
            #expect(store.overviewQuery == "")
        }
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

    @Test func deskRenaming() {
        let b1 = board("Google")
        let desk1 = desk("Main", boards: [b1], focusedBoardID: b1.id)

        withStore(desks: [desk1]) { store in
            // 1. Enter Den Mode, show rename panel
            store.isDenMode = true
            store.showRenameDeskPanel()
            #expect(store.isRenameDeskPanelPresented)

            // 2. Rename the desk to a custom name
            store.renameFocusedDesk(to: "Web Search")
            #expect(!store.isRenameDeskPanelPresented)
            #expect(store.focusedDesk?.label == "Web Search")

            // 3. Rename with empty name should be ignored (keep old name)
            store.showRenameDeskPanel()
            store.renameFocusedDesk(to: "")
            #expect(!store.isRenameDeskPanelPresented)
            #expect(store.focusedDesk?.label == "Web Search")
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

    @Test func reloadingFocusedBoardDoesNotChangeDenState() {
        let current = board("Current", url: "https://example.com/path")
        withStore(desks: [desk("Desk", boards: [current])]) { store in
            let stateBeforeReload = store.state

            store.reloadFocusedBoard()

            #expect(store.state == stateBeforeReload)
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

    @Test func denModeBoardWidthPanelAcceptsOnlyFitSelectionKeys() throws {
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
            #expect(KeyboardController.handle(select, store: store))
            #expect(!store.isBoardWidthPanelPresented)
            #expect(store.isDenMode)
            #expect(
                store.focusedDesk?.boards.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true)
        }
    }

    @Test func navigatingAnotherBoardFocusesIt() {
        let first = board("First")
        let second = board("Second")
        withStore(desks: [desk("Desk", boards: [first, second], focusedBoardID: first.id)]) { store in
            store.goBackInBoard(second.id)

            #expect(store.focusedDesk?.focusedBoardID == second.id)
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
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            ))
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
