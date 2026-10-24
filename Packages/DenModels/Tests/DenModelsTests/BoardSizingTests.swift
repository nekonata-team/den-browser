import DenApplication
import DenDomain
import DenModels
import Testing

@MainActor
struct BoardSizingTests {
    @Test(arguments: [false, true])
    func adjustmentUsesDeferredSaveOrImmediateSaveWhenNoDeferrerExists(hasDeferrer: Bool) {
        // Arrange
        let board = BoardState(label: "Board", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var immediate = 0
        var deferred = 0
        let deferSave: (() -> Void)? = hasDeferrer ? { deferred += 1 } : nil
        let sizing = BoardSizing(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks[0].boards[0].width == 600)
                immediate += 1
                return true
            }, deferredSave: deferSave)

        // Act
        sizing.adjustBoard(board.id, by: 80)

        // Assert
        #expect(shared.store.snapshot.den.desks[0].boards[0].width == 600)
        #expect(immediate == (hasDeferrer ? 0 : 1))
        #expect(deferred == (hasDeferrer ? 1 : 0))
    }

    @Test(arguments: [0.0, -80.0, 80.0])
    func deskAdjustmentClampsPrimaryWidthsAndSkipsSideBoards(delta: Double) {
        // Arrange
        let primary = BoardState(label: "Primary", width: 280, workingDirectory: "/tmp")
        let side = BoardState(width: 360, targetBoardID: primary.id)
        let desk = DeskState(label: "Desk", boards: [primary, side], focusedBoardID: primary.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var saves = 0
        let sizing = BoardSizing(store: shared.reader, writer: shared.writer, deferredSave: { saves += 1 })

        // Act
        sizing.adjustDesk(desk.id, by: delta)

        // Assert
        #expect(shared.store.snapshot.den.desks[0].boards.map(\.width) == [delta > 0 ? 360 : 280, 360])
        #expect(saves == (delta > 0 ? 1 : 0))
    }

    @Test(arguments: [100.0, 700.0, 2_000.0])
    func pairedPreviewPreservesOuterEdgesAndBothLimitsWithoutSaving(width: Double) {
        // Arrange
        let first = BoardState(label: "First", width: 520, workingDirectory: "/tmp")
        let second = BoardState(label: "Second", width: 760, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [first, second], focusedBoardID: first.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let sizing = BoardSizing(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                Issue.record("Preview must not save")
                return true
            })

        // Act
        sizing.resizePair(first.id, to: width)

        // Assert
        let widths = shared.store.snapshot.den.desks[0].boards.map(\.width)
        #expect(widths.reduce(0, +) == 1_280)
        #expect(widths.allSatisfy { (BoardState.minimumWidth...BoardState.maximumWidth).contains($0) })
        #expect(widths[0] == min(max(width, 280), 1_000))
    }

    @Test(arguments: [false, true])
    func mousePreviewSavesOnlyOnCommitAndSkipsSavingDuringDrag(dragging: Bool) {
        // Arrange
        let board = BoardState(label: "Board", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        var initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        if dragging { initial.activeDrag = .board(board.id) }
        let shared = DenStateStore.make(initialState: initial)
        var saved: [Double] = []
        let sizing = BoardSizing(
            store: shared.reader, writer: shared.writer,
            persist: {
                saved.append($0.desks[0].boards[0].width)
                return true
            })

        // Act
        sizing.resizeBoard(board.id, to: 2_000)
        let savesBeforeCommit = saved.count
        sizing.saveWidths()

        // Assert
        #expect(savesBeforeCommit == 0)
        #expect(shared.store.snapshot.den.desks[0].boards[0].width == 1_400)
        #expect(saved == (dragging ? [] : [1_400]))
    }

    @Test func fittingDeskKeepsUnconstrainedWidthAndRetainsStateAfterFailedSave() {
        // Arrange
        let primary = BoardState(label: "Primary", width: 520, workingDirectory: "/tmp")
        let side = BoardState(width: 360, targetBoardID: primary.id)
        let desk = DeskState(label: "Desk", boards: [primary, side], focusedBoardID: primary.id, scrollOffsetX: 180)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var saves = 0
        let sizing = BoardSizing(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                saves += 1
                return false
            })

        // Act
        let resized = sizing.resizeDesk(desk.id, to: 2_480)

        // Assert
        #expect(resized)
        #expect(shared.store.snapshot.den.desks[0].boards.map(\.width) == [2_480, 360])
        #expect(shared.store.snapshot.den.desks[0].scrollOffsetX == nil)
        #expect(saves == 1)
    }
}
