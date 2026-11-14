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
struct BoardRestorationTests {
    @Test func removingAndRestoringBoardRestoresSheetNavigationPause() {
        let board = BoardState(
            label: "Paused",
            width: 520,
            currentSheetURL: URL(string: "https://example.com/"),
            sheetNavigationPaused: true
        )
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [makeTestDesk("Desk", boards: [board], focusedBoardID: board.id)],
                        focusedDeskID: DeskID()
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.boardRemoval.removeFocusedBoard()

        #expect(session.resources.recentlyRemovedBoards.first?.board.sheetNavigationPaused == true)

        session.boardRemoval.restoreRecentlyRemovedBoard()

        #expect(session.navigation.focusedBoard?.sheetNavigationPaused == true)
    }

    @Test func removalHistoryKeepsNewestBoardsAndDoesNotPersistThem() throws {
        let boards = [makeTestBoard("First"), makeTestBoard("Second")]
        let source = makeTestDesk("Source", boards: boards, focusedBoardID: boards[0].id)
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

        session.boardRemoval.removeFocusedBoard()
        session.boardRemoval.removeFocusedBoard()
        let persisted = try #require(persistedState)

        #expect(session.resources.recentlyRemovedBoards.map { $0.board.id } == [boards[1].id, boards[0].id])
        #expect(persisted.desks[0].boards.isEmpty)
        #expect(
            DenProfileResources(state: DenStateNormalization.normalize(persisted)).recentlyRemovedBoards.isEmpty
        )
    }

    @Test func removalHistoryKeepsAtMostTenBoardsAndRestoresNewestFirst() {
        let boards = (0..<12).map { makeTestBoard("Board \($0)") }
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: boards, focusedBoardID: boards[0].id)])
                )
            )
        ) { session in
            for _ in 0..<11 {
                session.boardRemoval.removeFocusedBoard()
            }

            #expect(session.resources.recentlyRemovedBoards.count == BoardRemoval.maximumHistoryCount)
            #expect(
                session.resources.recentlyRemovedBoards.map { $0.board.id }
                    == Array((1...10).reversed()).map { boards[$0].id }
            )

            for _ in 0..<BoardRemoval.maximumHistoryCount {
                session.boardRemoval.restoreRecentlyRemovedBoard()
            }

            #expect(session.resources.recentlyRemovedBoards.isEmpty)
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == Array(1...11).map { boards[$0].id })
        }
    }

    @Test func restorationUsesOriginalDeskIndexAndBoardIdentity() {
        let boards = [makeTestBoard("First"), makeTestBoard("Restored", width: 760), makeTestBoard("Last")]
        let source = makeTestDesk("Source", boards: boards, focusedBoardID: boards[1].id)
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session in
            session.boardRemoval.removeFocusedBoard()
            session.boardRemoval.restoreRecentlyRemovedBoard()

            #expect(session.navigation.focusedDesk?.boards == boards)
            #expect(session.navigation.focusedDesk?.focusedBoardID == boards[1].id)
            #expect(session.resources.recentlyRemovedBoards.isEmpty)
        }
    }

    @Test func restorationCreatesANewBoardRuntime() throws {
        let removed = makeTestBoard("Removed")
        try withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    makeNativeTestState(desks: [makeTestDesk("Desk", boards: [removed])])
                )
            )
        ) { session in
            let originalRuntime = session.runtimes.webRuntime(for: removed)

            session.boardRemoval.removeFocusedBoard()
            #expect(session.resources.webRuntimes[removed.id] == nil)

            session.boardRemoval.restoreRecentlyRemovedBoard()
            let restoredBoard = try #require(session.navigation.focusedDesk?.boards.first)
            let restoredRuntime = session.runtimes.webRuntime(for: restoredBoard)
            #expect(restoredRuntime !== originalRuntime)
        }
    }

    @Test func restorationFallsBackRightOfFocusedBoardWhenSourceDeskIsGone() {
        let removed = makeTestBoard("Removed")
        let source = makeTestDesk("Source", boards: [removed])
        let targetBoards = [makeTestBoard("Before"), makeTestBoard("Focused"), makeTestBoard("After")]
        let target = makeTestDesk("Target", boards: targetBoards, focusedBoardID: targetBoards[1].id)
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target]))
            )
        ) { session in
            session.boardRemoval.removeFocusedBoard()
            session.desks.deleteFocusedDesk()
            session.boardRemoval.restoreRecentlyRemovedBoard()

            #expect(session.navigation.focusedDesk?.id == target.id)
            #expect(
                session.navigation.focusedDesk?.boards.map(\.id) == [
                    targetBoards[0].id, targetBoards[1].id, removed.id, targetBoards[2].id,
                ]
            )
            #expect(session.navigation.focusedDesk?.focusedBoardID == removed.id)
        }
    }
}
