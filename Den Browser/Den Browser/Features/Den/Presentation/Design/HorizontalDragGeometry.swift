import CoreGraphics
import Foundation

nonisolated enum HorizontalDragInsertion {
    static func groupedTargetIndex<ID: Hashable>(
        draggedID: ID,
        orderedGroups: [[ID]],
        desiredCenterX: CGFloat,
        frames: [ID: CGRect]
    ) -> Int? {
        guard let sourceIndex = orderedGroups.firstIndex(where: { $0.contains(draggedID) }) else {
            return nil
        }

        func frame(for group: [ID]) -> CGRect? {
            var result: CGRect?
            for id in group {
                guard let nextFrame = frames[id] else { return nil }
                result = result.map { $0.union(nextFrame) } ?? nextFrame
            }
            return result
        }

        func flattenedIndex(before groupIndex: Int) -> Int {
            orderedGroups[..<groupIndex].reduce(0) { $0 + $1.count }
        }

        if let nextIndex = orderedGroups.indices.dropFirst(sourceIndex + 1).first(where: {
            guard let nextFrame = frame(for: orderedGroups[$0]) else { return false }
            return desiredCenterX > nextFrame.midX
        }) {
            return flattenedIndex(before: nextIndex)
        }
        if let previousIndex = orderedGroups.indices.prefix(sourceIndex).reversed().first(where: {
            guard let previousFrame = frame(for: orderedGroups[$0]) else { return false }
            return desiredCenterX < previousFrame.midX
        }) {
            return flattenedIndex(before: previousIndex)
        }
        return nil
    }

    static func targetIndex<ID: Hashable>(
        draggedID: ID,
        orderedIDs: [ID],
        desiredCenterX: CGFloat,
        frames: [ID: CGRect],
        excludingIDs: Set<ID> = []
    ) -> Int? {
        guard let index = orderedIDs.firstIndex(of: draggedID) else { return nil }

        if let nextIndex = orderedIDs.indices.dropFirst(index + 1).first(where: {
            !excludingIDs.contains(orderedIDs[$0])
        }),
            let nextFrame = frames[orderedIDs[nextIndex]],
            desiredCenterX > nextFrame.midX
        {
            return nextIndex
        }
        if let previousIndex = orderedIDs.indices.prefix(index).reversed().first(where: {
            !excludingIDs.contains(orderedIDs[$0])
        }),
            let previousFrame = frames[orderedIDs[previousIndex]],
            desiredCenterX < previousFrame.midX
        {
            return previousIndex
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

    static func decision<ID: Hashable>(
        location: CGPoint,
        size: CGSize,
        draggedID: ID,
        orderedIDs: [ID],
        edge: CGFloat,
        excludingIDs: Set<ID> = []
    ) -> Decision<ID>? {
        guard location.y >= 0, location.y <= size.height,
            let index = orderedIDs.firstIndex(of: draggedID)
        else { return nil }

        let direction: Direction
        let targetID: ID
        let distanceToEdge: CGFloat
        if location.x < edge,
            let target = orderedIDs[..<index].reversed().first(where: { !excludingIDs.contains($0) })
        {
            direction = .leading
            targetID = target
            distanceToEdge = max(0, location.x)
        } else if location.x > size.width - edge,
            let target = orderedIDs.dropFirst(index + 1).first(where: { !excludingIDs.contains($0) })
        {
            direction = .trailing
            targetID = target
            distanceToEdge = max(0, size.width - location.x)
        } else {
            return nil
        }

        return Decision(
            direction: direction,
            targetID: targetID,
            distanceToEdge: distanceToEdge,
            interval: distanceToEdge < 16 ? 0.06 : 0.16
        )
    }
}

nonisolated enum OverviewDragGeometry {
    static func targetDeskID<ID: Hashable>(at location: CGPoint, frames: [ID: CGRect]) -> ID? {
        frames
            .filter { $0.value.minY <= location.y && location.y <= $0.value.maxY }
            .min { abs($0.value.midY - location.y) < abs($1.value.midY - location.y) }?
            .key
    }

    static func targetIndex<ID: Equatable>(
        draggedID: ID,
        orderedIDs: [ID],
        locationX: CGFloat,
        frames: [ID: CGRect]
    ) -> Int? {
        var targetIndex = 0
        for id in orderedIDs where id != draggedID {
            guard let frame = frames[id] else { return nil }
            if locationX < frame.midX { return targetIndex }
            targetIndex += 1
        }
        return targetIndex
    }
}
