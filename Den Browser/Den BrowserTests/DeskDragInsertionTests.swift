import Testing
@testable import Den_Browser

@MainActor
struct DeskDragInsertionTests {
    private let first = UUID.fixture(1)
    private let second = UUID.fixture(2)
    private let third = UUID.fixture(3)

    @Test func movesOnlyAfterCrossingNeighborCenter() {
        let frames = deskFrames
        let secondCenter = frames[second]?.midX ?? 0

        #expect(
            DeskDragInsertion.targetIndex(
                draggedDeskID: first,
                orderedDeskIDs: [first, second, third],
                desiredCenterX: secondCenter,
                frames: frames) == nil)
        #expect(
            DeskDragInsertion.targetIndex(
                draggedDeskID: first,
                orderedDeskIDs: [first, second, third],
                desiredCenterX: secondCenter + 1,
                frames: frames) == 1)
    }

    private var deskFrames: [UUID: CGRect] {
        [
            first: CGRect(x: 0, y: 0, width: 100, height: 30),
            second: CGRect(x: 108, y: 0, width: 100, height: 30),
            third: CGRect(x: 216, y: 0, width: 100, height: 30),
        ]
    }
}

private extension UUID {
    static func fixture(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
