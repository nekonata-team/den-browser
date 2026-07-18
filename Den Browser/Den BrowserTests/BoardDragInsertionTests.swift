import CoreGraphics
import Foundation
import Testing

@testable import Den_Browser

struct BoardDragInsertionTests {
    private let alpha = UUID.fixture(1)
    private let bravo = UUID.fixture(2)
    private let charlie = UUID.fixture(3)

    @Test func movesOnlyAfterCrossingNeighborCenter() {
        let frames = boardFrames
        let bravoCenter = frames[bravo]?.midX ?? 0

        #expect(
            BoardDragInsertion.targetIndex(
                draggedBoardID: alpha,
                orderedBoardIDs: [alpha, bravo, charlie],
                desiredCenterX: bravoCenter,
                frames: frames) == nil)
        #expect(
            BoardDragInsertion.targetIndex(
                draggedBoardID: alpha,
                orderedBoardIDs: [alpha, bravo, charlie],
                desiredCenterX: bravoCenter + 1,
                frames: frames) == 1)
    }

    @Test func movesLeftAfterCrossingPreviousCenter() {
        let frames = boardFrames

        #expect(
            BoardDragInsertion.targetIndex(
                draggedBoardID: charlie,
                orderedBoardIDs: [alpha, bravo, charlie],
                desiredCenterX: (frames[bravo]?.midX ?? 0) - 1,
                frames: frames) == 1)
    }

    @Test func ignoresEdgesAndMissingGeometry() {
        #expect(
            BoardDragInsertion.targetIndex(
                draggedBoardID: alpha,
                orderedBoardIDs: [alpha, bravo, charlie],
                desiredCenterX: -1,
                frames: [:]) == nil)
        #expect(
            BoardDragInsertion.targetIndex(
                draggedBoardID: UUID.fixture(99),
                orderedBoardIDs: [alpha, bravo, charlie],
                desiredCenterX: 1_000,
                frames: boardFrames) == nil)
    }

    private var boardFrames: [UUID: CGRect] {
        [
            alpha: CGRect(x: 0, y: 0, width: 100, height: 100),
            bravo: CGRect(x: 110, y: 0, width: 100, height: 100),
            charlie: CGRect(x: 220, y: 0, width: 100, height: 100),
        ]
    }
}

private extension UUID {
    static func fixture(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
