import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import GhosttyTerminal
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct BoardRemovalTests {
    @Test(arguments: [false, true])
    func removalActionsDelegateNeighborPreference(focusNext: Bool) {
        // Arrange
        let boards = [makeTestBoard("Before"), makeTestBoard("Selected"), makeTestBoard("After")]
        let source = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[1].id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: makeNativeTestState(desks: [source])),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }

        // Act
        AppActionHandler.perform(
            .board(focusNext ? .removeAndFocusNext : .remove),
            session: session,
            windowModel: composition.model
        )

        // Assert
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[0].id, boards[2].id])
        #expect(session.navigation.focusedBoard?.id == boards[focusNext ? 2 : 0].id)
        #expect(session.resources.recentlyRemovedBoards.first?.board.id == boards[1].id)
    }

    @Test func removingLastBoardClearsScrollOffsetX() {
        let onlyBoard = makeTestBoard("Only")
        var deskState = makeTestDesk("Desk", boards: [onlyBoard], focusedBoardID: onlyBoard.id)
        deskState.scrollOffsetX = 250.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(session.resources.state.desks[0].scrollOffsetX == 250.0)

        session.boardRemoval.removeBoard(onlyBoard.id)
        #expect(session.resources.state.desks[0].boards.isEmpty)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
    }

    @Test func removingFocusedBoardClearsScrollOffsetX() {
        let boardA = makeTestBoard("A")
        let boardB = makeTestBoard("B")
        var deskState = makeTestDesk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(session.resources.state.desks[0].scrollOffsetX == 350.0)

        session.boardRemoval.removeBoard(boardB.id)
        #expect(session.resources.state.desks[0].focusedBoardID == boardA.id)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
    }

    @Test func duplicatingFocusedBoardClearsScrollOffsetX() {
        let boardA = makeTestBoard("A")
        let boardB = makeTestBoard("B")
        var deskState = makeTestDesk("Desk", boards: [boardA, boardB], focusedBoardID: boardB.id)
        deskState.scrollOffsetX = 350.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(session.resources.state.desks[0].scrollOffsetX == 350.0)

        session.zmx.duplicateFocusedBoard()
        #expect(session.resources.state.desks[0].boards.count == 3)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
    }

    @Test func insertingFocusedBoardClearsScrollOffsetX() {
        let boardA = makeTestBoard("A")
        var deskState = makeTestDesk("Desk", boards: [boardA], focusedBoardID: boardA.id)
        deskState.scrollOffsetX = 200.0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(session.resources.state.desks[0].scrollOffsetX == 200.0)

        _ = session.boardOpening.createBoard(urlString: "https://example.com", focus: true)
        #expect(session.resources.state.desks[0].scrollOffsetX == nil)
    }

    @Test func deskStateFocusedBoardIDChangeClearsScrollOffsetX() {
        let boardA = makeTestBoard("A")
        let boardB = makeTestBoard("B")
        var deskState = makeTestDesk("Desk", boards: [boardA, boardB], focusedBoardID: boardA.id)
        deskState.scrollOffsetX = 150.0

        deskState.focusedBoardID = boardA.id
        #expect(deskState.scrollOffsetX == 150.0)

        deskState.focusedBoardID = boardB.id
        #expect(deskState.scrollOffsetX == nil)

        deskState.scrollOffsetX = 200.0
        deskState.focusedBoardID = nil
        #expect(deskState.scrollOffsetX == nil)
    }

    @Test func removingBoardDisposesItsRuntime() {
        let removed = makeTestBoard("Removed")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: [removed])])
                )
            )
        ) { session in
            let runtime = session.runtimes.webRuntime(for: removed)

            session.boardRemoval.removeFocusedBoard()

            #expect(session.resources.webRuntimes[removed.id] == nil)
            #expect(runtime.webView.navigationDelegate == nil)
            #expect(runtime.webView.uiDelegate == nil)
        }
    }
}
