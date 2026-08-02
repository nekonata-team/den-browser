import CoreGraphics
import Foundation

nonisolated enum HorizontalDragInsertion {
    static func targetIndex<ID: Equatable>(
        draggedID: ID,
        orderedIDs: [ID],
        desiredCenterX: CGFloat,
        frames: [ID: CGRect]
    ) -> Int? {
        guard let index = orderedIDs.firstIndex(of: draggedID) else { return nil }

        if orderedIDs.indices.contains(index + 1),
            let nextFrame = frames[orderedIDs[index + 1]],
            desiredCenterX > nextFrame.midX
        {
            return index + 1
        }
        if orderedIDs.indices.contains(index - 1),
            let previousFrame = frames[orderedIDs[index - 1]],
            desiredCenterX < previousFrame.midX
        {
            return index - 1
        }
        return nil
    }
}

nonisolated enum HorizontalDragAutoScroll {
    enum Direction: Equatable {
        case leading
        case trailing
    }

    struct Decision<ID> {
        let direction: Direction
        let targetID: ID
        let distanceToEdge: CGFloat
        let interval: TimeInterval
    }

    static func decision<ID: Equatable>(
        location: CGPoint,
        size: CGSize,
        draggedID: ID,
        orderedIDs: [ID],
        edge: CGFloat
    ) -> Decision<ID>? {
        guard location.y >= 0, location.y <= size.height,
            let index = orderedIDs.firstIndex(of: draggedID)
        else { return nil }

        let direction: Direction
        let targetIndex: Int
        let distanceToEdge: CGFloat
        if location.x < edge, index > 0 {
            direction = .leading
            targetIndex = index - 1
            distanceToEdge = max(0, location.x)
        } else if location.x > size.width - edge, index < orderedIDs.count - 1 {
            direction = .trailing
            targetIndex = index + 1
            distanceToEdge = max(0, size.width - location.x)
        } else {
            return nil
        }

        return Decision(
            direction: direction,
            targetID: orderedIDs[targetIndex],
            distanceToEdge: distanceToEdge,
            interval: distanceToEdge < 16 ? 0.06 : 0.16
        )
    }
}
