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
struct BoardDragTests {
    @Test func boardDragPersistsOnlyItsFinalOrder() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        let source = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var savedStates: [DenState] = []
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: {
                    savedStates.append($0)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.boardNavigation.beginBoardDrag(boards[0].id))
        session.resources.boardMovement.preview(
            boards[0].id,
            to: BoardIndex(rawValue: 2),
            in: session.navigation.presentedDeskID
        )
        #expect(savedStates.isEmpty)

        session.resources.boardMovement.finishDrag()
        #expect(savedStates.count == 1)
        #expect(savedStates[0].desks[0].boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
    }

    @Test func boardDragMovesSideBoardGroupAsOneBlock() {
        let target = makeTestBoard("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let middle = makeTestBoard("Middle")
        let last = makeTestBoard("Last")
        let boards = [target, side, middle, last]
        let source = makeTestDesk("Desk", boards: boards)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.boardNavigation.beginBoardDrag(target.id))
        session.resources.boardMovement.preview(
            target.id,
            to: BoardIndex(rawValue: 3),
            in: session.navigation.presentedDeskID
        )

        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [middle.id, last.id, target.id, side.id])
        session.resources.boardMovement.finishDrag()
    }

    @Test func boardAndDeskDragAreMutuallyExclusive() {
        let board = makeTestBoard("Board")
        let first = makeTestDesk("First", boards: [board], focusedBoardID: board.id)
        let second = makeTestDesk("Second")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.resources.deskMovement.beginDrag(second.id))
        #expect(session.resources.activeDrag == .desk(second.id))
        #expect(!session.boardNavigation.beginBoardDrag(board.id))
        #expect(!session.context.isBoardDragging)
        #expect(session.context.isDeskDragging)

        session.resources.deskMovement.finishDrag()
        #expect(session.boardNavigation.beginBoardDrag(board.id))
        #expect(session.resources.activeDrag == .board(board.id))
        #expect(!session.resources.deskMovement.beginDrag(second.id))
        #expect(session.context.isBoardDragging)
        #expect(!session.context.isDeskDragging)
    }

    @Test func cancelledBoardDragRestoresAndPersistsOriginalOrder() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        let source = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)
        var persistedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: {
                    persistedState = $0
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        #expect(session.boardNavigation.beginBoardDrag(boards[0].id))
        session.resources.boardMovement.preview(
            boards[0].id,
            to: BoardIndex(rawValue: 2),
            in: session.navigation.presentedDeskID
        )
        session.resources.boardMovement.restoreOrder(boards.map(\.id), in: source.id)
        session.resources.boardMovement.finishDrag()

        #expect(session.navigation.focusedDesk?.boards.map(\.id) == boards.map(\.id))
        #expect(persistedState?.desks[0].boards.map(\.id) == boards.map(\.id))
    }
}
