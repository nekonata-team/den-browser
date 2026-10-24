import DenApplication
import DenDomain
import Testing

nonisolated struct DeskDeletionTests {
    @Test(arguments: [false, true])
    func choosesAvailableDeskOnLeftBeforeTryingRight(_ farLeftAvailable: Bool) throws {
        // Arrange
        let farLeft = DeskState(label: "Far Left", boards: [])
        let nearLeft = DeskState(label: "Near Left", boards: [])
        let board = BoardState(label: "Removed", width: 520, currentSheetURL: nil)
        let removed = DeskState(label: "Removed", boards: [board])
        let right = DeskState(label: "Right", boards: [])
        let desks = [farLeft, nearLeft, removed, right]

        // Act
        let deletion = try #require(
            DeskDeletion.delete(
                removed.id, from: desks,
                isAvailable: { $0 == right.id || (farLeftAvailable && $0 == farLeft.id) }))

        // Assert
        #expect(deletion.desks == [farLeft, nearLeft, right])
        #expect(deletion.removedDesk == removed)
        #expect(deletion.replacementDeskID == (farLeftAvailable ? farLeft.id : right.id))
    }

    @Test func prefersNearestAvailableDeskOnLeft() throws {
        // Arrange
        let first = DeskState(label: "First", boards: [])
        let previous = DeskState(label: "Previous", boards: [])
        let removed = DeskState(label: "Removed", boards: [])
        let next = DeskState(label: "Next", boards: [])

        // Act
        let deletion = try #require(
            DeskDeletion.delete(removed.id, from: [first, previous, removed, next], isAvailable: { _ in true }))

        // Assert
        #expect(deletion.replacementDeskID == previous.id)
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
            deskID, from: desks, isAvailable: { _ in reason != .noAvailableReplacement })

        // Assert
        #expect(deletion == nil)
    }
}
