import DenDomain

public enum DeskDeletion {
    public struct Result {
        public let desks: [DeskState]
        public let removedDesk: DeskState
        public let replacementDeskID: DeskID
    }

    public static func delete(
        _ deskID: DeskID,
        from desks: [DeskState],
        isAvailable: (DeskID) -> Bool
    ) -> Result? {
        guard desks.count > 1, let deskIndex = desks.firstIndex(where: { $0.id == deskID }) else { return nil }
        let candidates = desks.prefix(deskIndex).reversed() + desks.dropFirst(deskIndex + 1)
        guard let replacementDeskID = candidates.first(where: { $0.id != deskID && isAvailable($0.id) })?.id else {
            return nil
        }
        var remainingDesks = desks
        let removedDesk = remainingDesks.remove(at: deskIndex)
        return Result(desks: remainingDesks, removedDesk: removedDesk, replacementDeskID: replacementDeskID)
    }
}
