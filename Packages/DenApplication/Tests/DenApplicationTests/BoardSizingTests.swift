import DenApplication
import DenDomain
import Testing

nonisolated struct BoardSizingTests {
    @Test func setBoardWidthReportsSaveFailureWithoutRevertingIntendedWidth() throws {
        // Arrange
        let board = BoardState(width: 640, workingDirectory: "/tmp")
        let desk = DeskState(label: "Work", boards: [board], focusedBoardID: board.id)
        var snapshot = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        var attemptedSave: DenState?
        let sizing = BoardSizing(
            store: DenStateReader { snapshot }, writer: DenStateWriter { $0(&snapshot) },
            persist: {
                attemptedSave = $0
                return false
            })

        // Act
        let result = sizing.setBoardWidth(board.id, to: 2_000, maximumWidth: 960)

        // Assert
        #expect(result == nil)
        #expect(snapshot.den.board(for: board.id)?.width == 960)
        #expect(attemptedSave == snapshot.den)
    }

    @Test(arguments: ["drag", "invalidWidth", "invalidMaximum", "missingBoard"])
    func setBoardWidthRejectsUnavailableOrInvalidInput(reason: String) {
        // Arrange
        let board = BoardState(width: 640, workingDirectory: "/tmp")
        let desk = DeskState(label: "Work", boards: [board], focusedBoardID: board.id)
        var snapshot = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        if reason == "drag" { snapshot.activeDrag = .board(board.id) }
        let before = snapshot.den
        let sizing = BoardSizing(
            store: DenStateReader { snapshot }, writer: DenStateWriter { $0(&snapshot) },
            persist: { _ in
                Issue.record("Rejected resize must not save")
                return true
            })

        // Act
        let result = sizing.setBoardWidth(
            reason == "missingBoard" ? BoardID() : board.id,
            to: reason == "invalidWidth" ? .infinity : 800,
            maximumWidth: reason == "invalidMaximum" ? .nan : 960)

        // Assert
        #expect(result == nil)
        #expect(snapshot.den == before)
    }
}
