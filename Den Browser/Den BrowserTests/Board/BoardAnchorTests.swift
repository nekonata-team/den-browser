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
struct BoardAnchorTests {
    @Test func toggleAnchorBoardSetsAndClearsAnchor() {
        let firstBoard = makeTestBoard("First")
        let secondBoard = makeTestBoard("Second")
        let source = makeTestDesk("Desk", boards: [firstBoard, secondBoard])
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            session.boardNavigation.focusBoard(firstBoard.id)

            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == firstBoard.id)
            #expect(session.feedback.latest?.message == "Set Anchor Board")

            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == nil)
            #expect(session.feedback.latest?.message == "Cleared Anchor Board")

            session.boardNavigation.focusBoard(secondBoard.id)
            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == secondBoard.id)
            #expect(session.feedback.latest?.message == "Set Anchor Board")
        }
    }

    @Test func toggleAnchorBoardForAnotherDeskKeepsCurrentFocus() {
        let focusedBoard = makeTestBoard("Focused")
        let targetBoard = makeTestBoard("Target")
        let focusedDesk = makeTestDesk("Current", boards: [focusedBoard], focusedBoardID: focusedBoard.id)
        let targetDesk = makeTestDesk("Overview", boards: [targetBoard])

        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [focusedDesk, targetDesk]))
            )
        ) { session in
            session.boardNavigation.focusBoard(focusedBoard.id)

            session.boardNavigation.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(
                session.resources.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID
                    == targetBoard.id
            )
            #expect(session.navigation.focusedDesk?.id == focusedDesk.id)
            #expect(session.navigation.focusedBoard?.id == focusedBoard.id)

            session.boardNavigation.toggleAnchorBoard(targetBoard.id, in: targetDesk.id)
            #expect(
                session.resources.state.desks.first(where: { $0.id == targetDesk.id })?.anchorBoardID == nil
            )
            #expect(session.navigation.focusedDesk?.id == focusedDesk.id)
            #expect(session.navigation.focusedBoard?.id == focusedBoard.id)
        }
    }

    @Test func jumpToAnchorBoardTogglesBetweenAnchorAndOrigin() {
        let firstBoard = makeTestBoard("First")
        let secondBoard = makeTestBoard("Second")
        let source = makeTestDesk("Desk", boards: [firstBoard, secondBoard])
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            session.boardNavigation.focusBoard(firstBoard.id)
            session.boardNavigation.toggleAnchorBoard()

            session.boardNavigation.focusBoard(secondBoard.id)
            #expect(session.navigation.focusedBoard?.id == secondBoard.id)

            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.navigation.focusedBoard?.id == firstBoard.id)

            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.navigation.focusedBoard?.id == secondBoard.id)
        }
    }

    @Test func jumpToAnchorBoardShowsWarningWhenNoAnchor() {
        let source = makeTestDesk("Desk", boards: [makeTestBoard("First")])
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.feedback.latest?.message == "No Anchor Board in Desk")
            #expect(session.feedback.latest?.severity == .warning)
        }
    }

    @Test func removingAnchorBoardClearsAnchor() {
        let firstBoard = makeTestBoard("First")
        let secondBoard = makeTestBoard("Second")
        let source = makeTestDesk("Desk", boards: [firstBoard, secondBoard])
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            session.boardNavigation.focusBoard(firstBoard.id)
            session.boardNavigation.toggleAnchorBoard()
            #expect(session.navigation.focusedDesk?.anchorBoardID == firstBoard.id)
            session.boardNavigation.focusBoard(secondBoard.id)
            session.boardNavigation.jumpToAnchorBoard()
            #expect(session.navigation.anchorJumpOriginBoardIDByDesk[source.id] == secondBoard.id)

            session.boardRemoval.removeBoard(firstBoard.id)
            #expect(session.navigation.focusedDesk?.anchorBoardID == nil)
            #expect(session.navigation.anchorJumpOriginBoardIDByDesk[source.id] == nil)
        }
    }
}
