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

    @Test func insertionSkipsOtherMembersOfDraggedGroup() throws {
        // Arrange
        let frames = horizontalFrames
        let beyondNextGroup = try #require(frames[third]).midX + 1
        let beforePreviousGroup = try #require(frames[first]).midX - 1

        // Act
        let primaryTarget = HorizontalDragInsertion.targetIndex(
            draggedID: first,
            orderedIDs: [first, second, third],
            desiredCenterX: beyondNextGroup,
            frames: frames,
            excludingIDs: [first, second])
        let sideTarget = HorizontalDragInsertion.targetIndex(
            draggedID: third,
            orderedIDs: [first, second, third],
            desiredCenterX: beforePreviousGroup,
            frames: frames,
            excludingIDs: [second, third])
        let ownMemberBoundary = HorizontalDragInsertion.targetIndex(
            draggedID: first,
            orderedIDs: [first, second],
            desiredCenterX: try #require(frames[second]).midX + 1,
            frames: frames,
            excludingIDs: [first, second])

        // Assert
        #expect(primaryTarget == 2)
        #expect(sideTarget == 0)
        #expect(ownMemberBoundary == nil)
    }

    @Test func groupedInsertionUsesWholeGroupCenterAndDoesNotReverse() throws {
        // Arrange
        let dragged = UUID.fixture(20)
        let primary = UUID.fixture(21)
        let side = UUID.fixture(22)
        let last = UUID.fixture(23)
        let frames = [
            dragged: CGRect(x: 0, y: 0, width: 100, height: 100),
            primary: CGRect(x: 110, y: 0, width: 100, height: 100),
            side: CGRect(x: 220, y: 0, width: 100, height: 100),
            last: CGRect(x: 330, y: 0, width: 100, height: 100),
        ]
        let orderedGroups = [[dragged], [primary, side], [last]]
        let groupCenter = try #require(frames[primary]).union(try #require(frames[side])).midX

        // Act
        let betweenMembers = HorizontalDragInsertion.groupedTargetIndex(
            draggedID: dragged,
            orderedGroups: orderedGroups,
            desiredCenterX: try #require(frames[primary]).midX + 1,
            frames: frames)
        let beyondGroupCenter = HorizontalDragInsertion.groupedTargetIndex(
            draggedID: dragged,
            orderedGroups: orderedGroups,
            desiredCenterX: groupCenter + 1,
            frames: frames)
        let reverseAcrossGroup = HorizontalDragInsertion.groupedTargetIndex(
            draggedID: dragged,
            orderedGroups: [[primary, side], [dragged], [last]],
            desiredCenterX: groupCenter + 1,
            frames: frames)

        // Assert
        #expect(betweenMembers == nil)
        #expect(beyondGroupCenter == 1)
        #expect(reverseAcrossGroup == nil)
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

    @Test func autoScrollSkipsOtherMembersOfDraggedGroup() {
        // Arrange
        let size = CGSize(width: 300, height: 100)

        // Act
        let trailing = HorizontalDragAutoScroll.decision(
            location: CGPoint(x: 290, y: 50),
            size: size,
            draggedID: first,
            orderedIDs: [first, second, third],
            edge: 40,
            excludingIDs: [first, second])
        let leading = HorizontalDragAutoScroll.decision(
            location: CGPoint(x: 10, y: 50),
            size: size,
            draggedID: third,
            orderedIDs: [first, second, third],
            edge: 40,
            excludingIDs: [second, third])

        // Assert
        #expect(leading?.targetID == first)
        #expect(trailing?.targetID == third)
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
