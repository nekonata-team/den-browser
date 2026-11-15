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
struct BoardFocusNavigationTests {
    @Test func boardFocusMovesAndWrapsAtBothEdges() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)])
                )
            )
        ) { session in
            session.boardNavigation.focusNextBoard()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)

            session.boardNavigation.focusPreviousBoard()
            session.boardNavigation.focusPreviousBoard()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)

            session.boardNavigation.focusNextBoard()
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)
        }
    }

    @Test func focusMovesDoNotSaveWhenThereIsOnlyOneTarget() {
        let board = makeTestBoard("Board")
        let onlyDesk = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [onlyDesk])),
                onSave: { _ in
                    saveCount += 1
                    return true
                }
            )
        ) { session in
            session.boardNavigation.focusNextDesk()
            session.boardNavigation.focusPreviousDesk()
            session.boardNavigation.focusNextBoard()
            session.boardNavigation.focusPreviousBoard()

            #expect(session.navigation.presentedDeskID == onlyDesk.id)
            #expect(session.navigation.focusedDesk?.focusedBoardID == board.id)
            #expect(saveCount == 0)
        }
    }

    @Test func reselectingPresentedDeskKeepsTransientEffectsWithoutSaving() {
        let board = makeTestBoard("Board")
        let onlyDesk = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0

        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [onlyDesk])),
                onSave: { _ in
                    saveCount += 1
                    return true
                }
            )
        ) { session, windowModel in
            windowModel.deskFilter.enter()
            windowModel.deskFilter.setQuery("board")
            windowModel.isDenMode = true
            session.notifications.recordNotification(title: "Build", body: "Finished", boardID: board.id)

            session.boardNavigation.focusDesk(onlyDesk.id)

            #expect(!windowModel.deskFilter.isPresented)
            #expect(windowModel.deskFilter.query.isEmpty)
            #expect(!windowModel.isDenMode)
            #expect(session.resources.notificationOperations.unreadCount() == 0)
            #expect(saveCount == 0)
        }
    }

    @Test func boardFocusRecoversWhenNoBoardIsFocused() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        let deskState = makeTestDesk("Desk", boards: boards)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [deskState], focusedDeskID: deskState.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.resources.state.desks[0].focusedBoardID = nil
        #expect(session.navigation.focusedDesk?.focusedBoardID == nil)

        session.boardNavigation.focusNextBoard()
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)

        session.resources.state.desks[0].focusedBoardID = nil
        session.boardNavigation.focusPreviousBoard()
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func boardBoundaryFocusStaysWithinSourceDesk() {
        let boards = [makeTestBoard("A"), makeTestBoard("B"), makeTestBoard("C")]
        let sourceDesk = makeTestDesk("Source", boards: boards, focusedBoardID: boards[1].id)
        let otherDesk = makeTestDesk("Other", boards: [makeTestBoard("Other Board")])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [sourceDesk, otherDesk], focusedDeskID: sourceDesk.id)
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.boardNavigation.focusFirstBoardInDesk(containing: boards[1].id)
        #expect(session.navigation.focusedDesk?.id == sourceDesk.id)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[0].id)

        session.boardNavigation.focusLastBoardInDesk(containing: boards[1].id)
        #expect(session.navigation.focusedDesk?.focusedBoardID == boards[2].id)
    }

    @Test func focusingAlreadyFocusedBoardDoesNotSaveAgain() {
        let board = makeTestBoard("Focused")
        let source = makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)
        var saveCount = 0
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [source], focusedDeskID: source.id)),
                onSave: { _ in
                    saveCount += 1
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.boardNavigation.focusBoard(board.id)

        #expect(saveCount == 0)
    }

    @Test func reloadingFocusedBoardDoesNotChangeDenState() {
        let current = makeTestBoard("Current", url: "https://example.com/path")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: [current])])
                )
            )
        ) { session in
            let stateBeforeReload = session.resources.state

            session.boardOpening.reloadFocusedBoard()

            #expect(session.resources.state == stateBeforeReload)
        }
    }

    @Test func navigatingAnotherBoardFocusesIt() {
        let first = makeTestBoard("First")
        let second = makeTestBoard("Second")
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [
                        makeTestDesk("Desk", boards: [first, second], focusedBoardID: first.id)
                    ])
                )
            )
        ) { session in
            session.boardOpening.goBackInBoard(second.id)

            #expect(session.navigation.focusedDesk?.focusedBoardID == second.id)
        }
    }
}
