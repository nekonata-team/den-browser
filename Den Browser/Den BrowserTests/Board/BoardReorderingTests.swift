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
struct BoardReorderingTests {
    @Test func boardMovementAvailabilityStopsAtDeskEdges() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards)])
                )
            )
        ) { session in
            #expect(!session.resources.boardMovement.canMove(boards[0].id, by: -1))
            #expect(session.resources.boardMovement.canMove(boards[0].id, by: 1))
            #expect(session.resources.boardMovement.canMove(boards[1].id, by: -1))
            #expect(session.resources.boardMovement.canMove(boards[1].id, by: 1))
            #expect(session.resources.boardMovement.canMove(boards[2].id, by: -1))
            #expect(!session.resources.boardMovement.canMove(boards[2].id, by: 1))
        }
    }

    @Test func reorderingBoardKeepsItFocusedAndStopsAtDeskEdge() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards, focusedBoardID: boards[1].id)])
                )
            )
        ) { session, windowModel in
            session.boardNavigation.moveFocusedBoardLeft()
            session.boardNavigation.moveFocusedBoardLeft()

            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[0].id, boards[2].id,
                ]
            )
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(windowModel.centerFocusedBoardRequest == 1)
        }
    }

    @Test func reorderingBoardToTargetIndexUpdatesAndPersistsOrder() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        var persistedState: DenState?
        let deskState = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id)),
                onSave: {
                    persistedState = $0
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.resources.boardMovement.preview(
            boards[0].id,
            to: BoardIndex(rawValue: 2),
            in: session.navigation.presentedDeskID
        )
        session.resources.save()

        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
        #expect(persistedState?.desks[0].boards.map(\.id) == [boards[1].id, boards[2].id, boards[0].id])
    }

    @Test func sideBoardMovesWithTargetAndIsRestoredWithItAfterRemoval() {
        let target = makeTestBoard("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let after = makeTestBoard("After")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [
                        makeTestDesk("Desk", boards: [target, side, after], focusedBoardID: target.id)
                    ])
                )
            )
        ) { session in
            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(!session.resources.boardMovement.canMove(side.id, by: 1))

            session.boardRemoval.removeBoard(target.id)
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [after.id])
            #expect(session.resources.recentlyRemovedBoards.first?.sideBoard?.id == side.id)

            session.boardRemoval.restoreRecentlyRemovedBoard()
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [after.id, target.id, side.id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == target.id)
        }
    }

    @Test func restoringRemovedSideBoardFollowsTargetToItsCurrentDesk() {
        let target = makeTestBoard("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = makeTestDesk("Source", boards: [target, side], focusedBoardID: side.id)
        let destination = makeTestDesk("Destination")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, destination]))
            )
        ) { session in
            session.boardRemoval.removeBoard(side.id)
            session.boardNavigation.focusBoard(target.id)
            session.boardNavigation.moveFocusedBoardToNextDesk()

            session.boardRemoval.restoreRecentlyRemovedBoard()

            #expect(session.resources.state.desks[0].boards.isEmpty)
            #expect(session.resources.state.desks[1].boards.map(\.id) == [target.id, side.id])
            #expect(session.navigation.focusedDesk?.focusedBoardID == side.id)
        }
    }

    @Test func movingInspectionBoardToDeskCarriesTargetGroup() {
        let target = makeTestBoard("Target")
        let side = BoardState(width: 390, targetBoardID: target.id)
        let source = makeTestDesk("Source", boards: [target, side], focusedBoardID: side.id)
        let destinationBoard = makeTestBoard("Destination")
        let destination = makeTestDesk("Destination", boards: [destinationBoard], focusedBoardID: destinationBoard.id)
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, destination]))
            )
        ) { session in
            session.boardNavigation.moveFocusedBoardToNextDesk()

            #expect(session.resources.state.desks[0].boards.isEmpty)
            #expect(
                session.resources.state.desks[1].boards.map(\.id) == [
                    destinationBoard.id, target.id, side.id,
                ]
            )
            #expect(session.navigation.focusedDesk?.focusedBoardID == side.id)
            #expect(session.navigation.focusedBoard?.width == 390)
        }
    }

    @Test func reorderingBoardWithScrollOffsetSavesOnceAndCenters() {
        let boards = [makeTestBoard("A"), makeTestBoard("B")]
        var source = makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)
        source.scrollOffsetX = 180
        var saveCount = 0

        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source])),
                onSave: { _ in
                    saveCount += 1
                    return true
                }
            )
        ) { session, windowModel in
            session.boardNavigation.moveFocusedBoardRight()

            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [boards[1].id, boards[0].id])
            #expect(session.resources.state.desks[0].scrollOffsetX == nil)
            #expect(windowModel.centerFocusedBoardRequest == 1)
            #expect(saveCount == 1)
        }
    }

    @Test func rapidBoardReorderingKeepsFocusAndRequestsCentering() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C"), makeTestBoard("D")]
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)])
                )
            )
        ) { session, windowModel in
            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[0].id, boards[2].id, boards[3].id,
                ]
            )
            #expect(windowModel.centerFocusedBoardRequest == 1)

            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[2].id, boards[0].id, boards[3].id,
                ]
            )
            #expect(windowModel.centerFocusedBoardRequest == 2)

            session.boardNavigation.moveFocusedBoardRight()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    boards[1].id, boards[2].id, boards[3].id, boards[0].id,
                ]
            )
            #expect(windowModel.centerFocusedBoardRequest == 3)
        }
    }

    @Test func movingBoardToDeskPlacesItAfterTargetAndFocusesIt() {
        let moved = makeTestBoard("Moved")
        let targetBoards = [makeTestBoard("Before"), makeTestBoard("Target"), makeTestBoard("After")]
        let source = makeTestDesk("Source", boards: [moved])
        let target = makeTestDesk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target]))
            )
        ) { session in
            session.boardNavigation.moveFocusedBoardToNextDesk()

            #expect(session.resources.state.desks[0].boards.isEmpty)
            #expect(session.resources.state.desks[0].focusedBoardID == nil)
            #expect(
                session.resources.state.desks[1].boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, moved.id, targetBoards[2].id,
                ]
            )
            #expect(session.navigation.focusedDesk?.id == target.id)
            #expect(session.navigation.focusedDesk?.focusedBoardID == moved.id)
        }
    }
}
