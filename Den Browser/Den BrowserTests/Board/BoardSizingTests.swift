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
struct BoardSizingTests {
    @Test func adjustsEveryBoardInFocusedDeskWithinBounds() {
        let primary = makeTestBoard("Narrow", width: 280)
        let side = BoardState(label: "Inspection Board", width: 360, targetBoardID: primary.id)
        let boards = [primary, side, makeTestBoard("Wide", width: 1_400)]
        let otherBoard = makeTestBoard("Other", width: 760)
        let firstDesk = makeTestDesk("First", boards: boards, focusedBoardID: boards[0].id)
        let secondDesk = makeTestDesk("Second", boards: [otherBoard])
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [firstDesk, secondDesk]))
            )
        ) { session, windowModel in
            windowModel.toggleFocusedBoardMaximized()

            windowModel.adjustFocusedDeskBoardWidths(by: -80)
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [280, 360, 1_320])
            #expect(session.resources.state.desks[1].boards.map(\.width) == [760])
            #expect(windowModel.maximizedBoardID == nil)

            windowModel.adjustFocusedDeskBoardWidths(by: 160)
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [440, 360, 1_400])
        }
    }

    @Test func resizesEveryBoardInFocusedDeskToFitCurrentWindow() {
        let first = makeTestBoard("First", width: 440)
        let side = BoardState(label: "Inspection Board", width: 360, targetBoardID: first.id)
        let firstBoards = [first, side, makeTestBoard("Second", width: 760)]
        let otherBoard = makeTestBoard("Other", width: 980)
        let firstDesk = makeTestDesk("First", boards: firstBoards, focusedBoardID: firstBoards[0].id)
        let secondDesk = makeTestDesk("Second", boards: [otherBoard])
        var saveCount = 0
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [firstDesk, secondDesk])),
                onSave: { _ in
                    saveCount += 1
                    return true
                }
            )
        ) { session, windowModel in
            windowModel.updateBoardLayout(availableWidth: 1_180, spacing: 10)
            windowModel.toggleFocusedBoardMaximized()
            session.resources.state.desks[0].scrollOffsetX = 180
            let centerRequest = windowModel.centerFocusedBoardRequest
            let saveCountBeforeResize = saveCount

            #expect(windowModel.resizeFocusedDeskBoards(toFit: 3))
            #expect(
                session.navigation.focusedDesk?.boards.filter { !$0.isSideBoard }.allSatisfy {
                    abs($0.width - 386.666_666_666_666_7) < 0.001
                } == true
            )
            #expect(session.navigation.focusedDesk?.boards[1].width == 360)
            #expect(session.resources.state.desks[1].boards[0].width == 980)
            #expect(session.resources.state.desks[0].scrollOffsetX == nil)
            #expect(windowModel.maximizedBoardID == nil)
            #expect(windowModel.centerFocusedBoardRequest == centerRequest + 1)
            #expect(saveCount == saveCountBeforeResize + 1)
        }
    }

    @Test func rejectsBoardFitCountsOutsideCurrentWidth() {
        let boards = [makeTestBoard("First"), makeTestBoard("Second")]
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards)])
                )
            )
        ) { session, windowModel in
            #expect(windowModel.boardLayoutMetrics == nil)
            #expect(windowModel.boardWidth(toFit: 3) == nil)

            windowModel.updateBoardLayout(availableWidth: 1_080, spacing: 10)

            #expect(
                windowModel.boardLayoutMetrics
                    == BoardLayoutMetrics(availableWidth: 1_080, spacing: 10)
            )
            #expect(windowModel.boardWidth(toFit: 3) != nil)
            #expect(windowModel.boardWidth(toFit: 4) == nil)
            #expect(!windowModel.resizeFocusedDeskBoards(toFit: 4))
            #expect(session.navigation.focusedDesk?.boards.map(\.width) == [520, 520])
        }
    }

    @Test func oneBoardFitUsesFullWindowBeyondManualResizeLimit() {
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: [makeTestBoard("Wide")])])
                )
            )
        ) { session, windowModel in
            windowModel.updateBoardLayout(availableWidth: 2_480, spacing: 10)

            #expect(windowModel.resizeFocusedDeskBoards(toFit: 1))
            #expect(session.navigation.focusedDesk?.boards[0].width == 2_480)
        }
    }
}
