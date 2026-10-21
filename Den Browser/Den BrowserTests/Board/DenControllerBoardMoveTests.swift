import DenDomain
import Testing

@testable import Den_Browser

@MainActor
struct DenControllerBoardMoveTests {
    @Test(arguments: [false, true], [false, true])
    func movingGroupPreservesDeskFocusAndSavesOrder(sameDesk: Bool, atEnd: Bool) throws {
        // Arrange
        let moved = BoardState(label: "Moved", width: 520, currentSheetURL: nil)
        let side = BoardState(width: 390, targetBoardID: moved.id)
        let first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let last = BoardState(label: "Last", width: 520, currentSheetURL: nil)
        let source = DeskState(
            label: "Source", boards: atEnd ? [moved, side, first] : [first, moved, side], focusedBoardID: side.id)
        let target = DeskState(label: "Target", boards: [last])
        var saved: DenState?
        let recordSave: (DenState) -> Bool = {
            saved = $0
            return true
        }
        try withTestController(desks: [source, target], onSave: recordSave) { controller in
            let deskID = sameDesk ? source.id : target.id
            let anchorID = atEnd ? nil : (sameDesk ? first.id : last.id)

            // Act
            let result = controller.moveBoardGroup(side.id, to: deskID, before: anchorID)

            // Assert
            #expect(result)
            #expect(controller.presentedDeskID == source.id)
            let destination = try #require(controller.state.desks.first(where: { $0.id == deskID }))
            let otherIDs = sameDesk ? [first.id] : [last.id]
            #expect(
                destination.boards.map(\.id)
                    == (atEnd ? otherIDs + [moved.id, side.id] : [moved.id, side.id] + otherIDs))
            #expect(destination.focusedBoardID == (sameDesk ? side.id : last.id))
            #expect(controller.state.desks[0].focusedBoardID == (sameDesk ? side.id : first.id))
            #expect(saved?.desks == controller.state.desks)
        }
    }

    @Test func transferToEmptyDeskAssignsFocusWithoutSwitchingDesk() {
        // Arrange
        let board = BoardState(label: "Moved", width: 520, currentSheetURL: nil)
        let source = DeskState(label: "Source", boards: [board])
        let target = DeskState(label: "Target", boards: [])
        withTestController(desks: [source, target]) { controller in
            // Act
            let result = controller.moveBoardGroup(board.id, to: target.id, before: nil)

            // Assert
            #expect(result)
            #expect(controller.presentedDeskID == source.id)
            #expect(controller.state.desks[0].focusedBoardID == nil)
            #expect(controller.state.desks[1].focusedBoardID == board.id)
        }
    }
}
