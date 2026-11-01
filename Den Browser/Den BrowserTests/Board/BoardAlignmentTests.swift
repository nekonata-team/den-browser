import DenDomain
import DenModels
import Testing

@testable import DenViews
@testable import Den_Browser

@MainActor
struct BoardAlignmentTests {
    @Test func resizePreviewKeepsTheFocusedBoardCenteredAcrossRepeatedWidthChanges() {
        // Arrange
        let boards = (0..<4).map { BoardState(label: "Board \($0)", width: 520, currentSheetURL: nil) }
        func parameters(width: Double) -> BoardLayout.Parameters {
            var resized = boards
            for index in resized.indices { resized[index].width = width }
            return BoardLayout.Parameters(
                centering: .always, boards: resized, maximizedBoardID: nil,
                windowWidth: 1_000, horizontalPadding: 10, spacing: 8)
        }
        let original = parameters(width: 520)
        let focusedIndex = 2
        let origin = BoardLayout.scrollTargetAfterLayoutChange(
            for: boards[focusedIndex].id, in: original, currentScrollX: 0)!
        let preview = BoardWidthPreview(
            deskID: DeskID(), scrollOffsetX: origin,
            contentWidth: BoardLayout.contentWidth(for: original), centeringRequest: 0)

        for width in [600.0, 680, 600, 360] {
            // Act
            let resized = parameters(width: width)
            let target = BoardLayout.scrollTargetAfterLayoutChange(
                for: boards[focusedIndex].id, in: resized, currentScrollX: origin)!
            let range = BoardLayout.boardContentRange(for: focusedIndex, in: resized)!
            let displayedCenter = (range.minX + range.maxX) / 2 + preview.translation(to: target) - origin

            // Assert
            #expect(abs(displayedCenter - original.windowWidth / 2) < 0.001)
            let nativeContentWidth = max(
                preview.minimumContentWidth(containerWidth: original.windowWidth),
                BoardLayout.contentWidth(for: resized))
            #expect(nativeContentWidth - original.windowWidth >= origin)
        }
        for containerWidth in [500.0, 1_000, 3_000] {
            #expect(preview.minimumContentWidth(containerWidth: containerWidth) - containerWidth >= origin)
        }
    }

    @Test func newerAlignmentRequestInvalidatesOlderCompletion() {
        let deskID = DeskID()
        let boardID = BoardID()
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
        #expect(!newer.isRelevant(to: DeskID(), boardIDs: Set([boardID]), layoutKey: layoutKey))
        #expect(!newer.isRelevant(to: deskID, boardIDs: [], layoutKey: layoutKey))
    }

    @Test func pendingBoardAlignmentIsCancelledForDifferentDesk() {
        let deskA = DeskID()
        let deskB = DeskID()
        let boardID = BoardID()
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
        let leftBoard = BoardID()
        let focusedBoard = BoardID()
        let insertedBoard = BoardID()
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
        let leftBoard = BoardID()
        let removedBoard = BoardID()
        let focusedBoard = BoardID()
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
