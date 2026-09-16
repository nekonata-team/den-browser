import Testing

@testable import Den_Browser

@MainActor
struct BoardAlignmentTests {
    @Test func newerAlignmentRequestInvalidatesOlderCompletion() {
        let deskID = UUID()
        let boardID = UUID()
        let layoutKey = BoardStripLayoutKey(
            ids: [boardID],
            widths: [520],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let older = PendingBoardAlignment(
            deskID: deskID,
            boardID: boardID,
            kind: .resting(120),
            animated: false,
            layoutKey: layoutKey)
        let newer = PendingBoardAlignment(
            deskID: deskID,
            boardID: boardID,
            kind: .center,
            animated: true,
            layoutKey: layoutKey)

        #expect(!PendingBoardAlignment.isCurrent(older, in: newer))
        #expect(PendingBoardAlignment.isCurrent(newer, in: newer))
        #expect(newer.isRelevant(to: deskID, boardIDs: Set([boardID]), layoutKey: layoutKey))
        #expect(!newer.isRelevant(to: UUID(), boardIDs: Set([boardID]), layoutKey: layoutKey))
        #expect(!newer.isRelevant(to: deskID, boardIDs: [], layoutKey: layoutKey))
    }

    @Test func pendingBoardAlignmentIsCancelledForDifferentDesk() {
        let deskA = UUID()
        let deskB = UUID()
        let boardID = UUID()
        let layoutKey = BoardStripLayoutKey(
            ids: [boardID],
            widths: [520],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let pending = PendingBoardAlignment(
            deskID: deskA,
            boardID: boardID,
            kind: .center,
            animated: false,
            layoutKey: layoutKey)

        #expect(!pending.isRelevant(to: deskB, boardIDs: Set([boardID]), layoutKey: layoutKey))
        #expect(pending.isRelevant(to: deskA, boardIDs: Set([boardID]), layoutKey: layoutKey))
    }

    @Test func centeredScrollTargetCalculatedFromLayoutParametersMatchesExpectedOffset() {
        let board1 = BoardState(label: "1", width: 600, currentSheetURL: nil)
        let board2 = BoardState(label: "2", width: 600, currentSheetURL: nil)
        let boards = [board1, board2]
        let params = BoardLayout.Parameters(
            centering: .always,
            boards: boards,
            maximizedBoardID: nil,
            windowWidth: 1_000,
            horizontalPadding: 10,
            spacing: 10
        )
        let contentWidth = BoardLayout.contentWidth(for: params)

        let target0 = BoardLayout.centeredScrollX(
            for: 0,
            in: params,
            containerWidth: 1_000,
            contentWidth: contentWidth
        )
        let target1 = BoardLayout.centeredScrollX(
            for: 1,
            in: params,
            containerWidth: 1_000,
            contentWidth: contentWidth
        )

        #expect(target0 != nil)
        #expect(target1 != nil)
        #expect(target0 != target1)
    }

    @Test func insertedBoardWidthBeforeFocusedBoardIncludesItsSpacing() {
        let leftBoard = UUID()
        let focusedBoard = UUID()
        let insertedBoard = UUID()
        let previous = BoardStripLayoutKey(
            ids: [leftBoard, focusedBoard],
            widths: [400, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let current = BoardStripLayoutKey(
            ids: [leftBoard, insertedBoard, focusedBoard],
            widths: [400, 320, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)

        #expect(current.insertedWidth(before: focusedBoard, comparedTo: previous, spacing: 12) == 332)
        #expect(current.insertedWidth(before: leftBoard, comparedTo: previous, spacing: 12) == 0)
        #expect(current.insertedWidth(before: focusedBoard, comparedTo: current, spacing: 12) == 0)
    }

    @Test func removedBoardWidthBeforeFocusedBoardIncludesItsSpacing() {
        let leftBoard = UUID()
        let removedBoard = UUID()
        let focusedBoard = UUID()
        let previous = BoardStripLayoutKey(
            ids: [leftBoard, removedBoard, focusedBoard],
            widths: [400, 320, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)
        let current = BoardStripLayoutKey(
            ids: [leftBoard, focusedBoard],
            widths: [400, 600],
            maximizedBoardID: nil,
            windowWidth: 1_000)

        #expect(previous.removedWidth(before: focusedBoard, comparedTo: current, spacing: 12) == 332)
        #expect(previous.removedWidth(before: leftBoard, comparedTo: current, spacing: 12) == 0)
    }
}
