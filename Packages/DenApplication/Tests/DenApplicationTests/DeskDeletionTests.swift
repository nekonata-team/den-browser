import DenApplication
import DenDomain
import Testing

nonisolated struct DeskDeletionTests {
    nonisolated enum ReplacementPriority: CaseIterable, Sendable {
        case nearestLeft
        case farLeft
        case rightFallback
    }

    @Test(arguments: ReplacementPriority.allCases)
    func choosesNearestAvailableDeskOnLeftBeforeTryingRight(_ priority: ReplacementPriority) throws {
        // Arrange
        let farLeft = DeskState(label: "Far Left", boards: [])
        let nearLeft = DeskState(label: "Near Left", boards: [])
        let board = BoardState(label: "Removed", width: 520, currentSheetURL: nil)
        let removed = DeskState(label: "Removed", boards: [board])
        let right = DeskState(label: "Right", boards: [])
        let desks = [farLeft, nearLeft, removed, right]
        let expectedID: DeskID
        let availableIDs: Set<DeskID>
        switch priority {
        case .nearestLeft:
            expectedID = nearLeft.id
            availableIDs = [farLeft.id, nearLeft.id, right.id]
        case .farLeft:
            expectedID = farLeft.id
            availableIDs = [farLeft.id, right.id]
        case .rightFallback:
            expectedID = right.id
            availableIDs = [right.id]
        }

        // Act
        let deletion = try #require(
            DeskDeletion.delete(removed.id, from: desks, isAvailable: { availableIDs.contains($0) })
        )

        // Assert
        #expect(deletion.desks == [farLeft, nearLeft, right])
        #expect(deletion.removedDesk == removed)
        #expect(deletion.replacementDeskID == expectedID)
    }

    nonisolated enum UnavailableDeletion: CaseIterable, Sendable {
        case lastDesk
        case missingDesk
        case noAvailableReplacement
    }

    @Test(arguments: UnavailableDeletion.allCases)
    func rejectsDeletionWithoutExistingTargetAndAvailableReplacement(_ reason: UnavailableDeletion) {
        // Arrange
        let target = DeskState(label: "Target", boards: [])
        let other = DeskState(label: "Other", boards: [])
        let desks = reason == .lastDesk ? [target] : [target, other]
        let deskID = reason == .missingDesk ? DeskID() : target.id

        // Act
        let deletion = DeskDeletion.delete(
            deskID,
            from: desks,
            isAvailable: { _ in reason != .noAvailableReplacement }
        )

        // Assert
        #expect(deletion == nil)
    }
}
