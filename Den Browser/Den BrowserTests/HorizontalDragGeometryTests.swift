import CoreGraphics
import Testing

@testable import Den_Browser

@MainActor
struct HorizontalDragGeometryTests {
    private let first = UUID.fixture(1)
    private let second = UUID.fixture(2)
    private let third = UUID.fixture(3)

    @Test func insertionMovesOnlyAfterCrossingNeighborCenter() {
        let frames = horizontalFrames
        let secondCenter = frames[second]?.midX ?? 0

        #expect(
            HorizontalDragInsertion.targetIndex(
                draggedID: first,
                orderedIDs: [first, second, third],
                desiredCenterX: secondCenter,
                frames: frames) == nil)
        #expect(
            HorizontalDragInsertion.targetIndex(
                draggedID: first,
                orderedIDs: [first, second, third],
                desiredCenterX: secondCenter + 1,
                frames: frames) == 1)
        #expect(
            HorizontalDragInsertion.targetIndex(
                draggedID: third,
                orderedIDs: [first, second, third],
                desiredCenterX: secondCenter - 1,
                frames: frames) == 1)
    }

    @Test func insertionIgnoresMissingGeometryAndUnknownID() {
        #expect(
            HorizontalDragInsertion.targetIndex(
                draggedID: first,
                orderedIDs: [first, second, third],
                desiredCenterX: -1,
                frames: [:]) == nil)
        #expect(
            HorizontalDragInsertion.targetIndex(
                draggedID: UUID.fixture(99),
                orderedIDs: [first, second, third],
                desiredCenterX: 1_000,
                frames: horizontalFrames) == nil)
    }

    @Test func autoScrollTargetsAdjacentIDAtLeadingAndTrailingEdges() {
        let leading = HorizontalDragAutoScroll.decision(
            location: CGPoint(x: 10, y: 50),
            size: CGSize(width: 300, height: 100),
            draggedID: second,
            orderedIDs: [first, second, third],
            edge: 40)
        #expect(leading?.targetID == first)
        #expect(leading?.direction == .leading)
        #expect(leading?.distanceToEdge == 10)
        #expect(leading?.interval == 0.06)

        let trailing = HorizontalDragAutoScroll.decision(
            location: CGPoint(x: 280, y: 50),
            size: CGSize(width: 300, height: 100),
            draggedID: second,
            orderedIDs: [first, second, third],
            edge: 40)
        #expect(trailing?.targetID == third)
        #expect(trailing?.direction == .trailing)
        #expect(trailing?.distanceToEdge == 20)
        #expect(trailing?.interval == 0.16)
    }

    @Test func autoScrollRejectsOutsideEdgeAndBoundary() {
        let outside = HorizontalDragAutoScroll.decision(
            location: CGPoint(x: 50, y: -1),
            size: CGSize(width: 300, height: 100),
            draggedID: second,
            orderedIDs: [first, second, third],
            edge: 40)
        #expect(outside == nil)

        let firstAtLeadingEdge = HorizontalDragAutoScroll.decision(
            location: CGPoint(x: 10, y: 50),
            size: CGSize(width: 300, height: 100),
            draggedID: first,
            orderedIDs: [first, second, third],
            edge: 40)
        #expect(firstAtLeadingEdge == nil)

        let missingID = HorizontalDragAutoScroll.decision(
            location: CGPoint(x: 10, y: 50),
            size: CGSize(width: 300, height: 100),
            draggedID: UUID.fixture(99),
            orderedIDs: [first, second, third],
            edge: 40)
        #expect(missingID == nil)
    }

    @Test func overviewInsertionUsesBoardHalvesAndSupportsEmptyDesk() {
        let desk = UUID.fixture(10)
        let emptyDesk = UUID.fixture(11)
        let frames = [
            first: CGRect(x: 0, y: 0, width: 100, height: 100),
            second: CGRect(x: 110, y: 0, width: 100, height: 100),
        ]

        #expect(
            OverviewDragGeometry.targetDeskID(
                at: CGPoint(x: 20, y: 40),
                frames: [desk: CGRect(x: 0, y: 0, width: 240, height: 120)]) == desk)
        #expect(
            OverviewDragGeometry.targetIndex(
                draggedID: first,
                orderedIDs: [first, second],
                locationX: 120,
                frames: frames) == 0)
        #expect(
            OverviewDragGeometry.targetIndex(
                draggedID: first,
                orderedIDs: [first, second],
                locationX: 220,
                frames: frames) == 1)
        #expect(
            OverviewDragGeometry.targetIndex(
                draggedID: first,
                orderedIDs: [],
                locationX: 0,
                frames: [:]) == 0)
        #expect(
            OverviewDragGeometry.targetDeskID(
                at: CGPoint(x: 20, y: 200),
                frames: [emptyDesk: CGRect(x: 0, y: 300, width: 240, height: 120)]) == nil)
    }

    private var horizontalFrames: [UUID: CGRect] {
        [
            first: CGRect(x: 0, y: 0, width: 100, height: 100),
            second: CGRect(x: 110, y: 0, width: 100, height: 100),
            third: CGRect(x: 220, y: 0, width: 100, height: 100),
        ]
    }
}

private extension UUID {
    static func fixture(_ value: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    }
}
