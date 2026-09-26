import Testing

@testable import Den_Browser

@MainActor
struct PersonalDeskPresetTests {
    @Test(arguments: [false, true])
    func captureKeepsTargetFocusWhenOmittingInspection(focusInspection: Bool) {
        // Arrange
        let other = BoardState(label: "Other", width: 520, currentSheetURL: nil)
        let target = BoardState(label: "Target", width: 520, currentSheetURL: nil)
        let inspection = BoardState(width: 360, targetBoardID: target.id)
        let desk = DeskState(
            label: "Research",
            boards: [other, target, inspection],
            focusedBoardID: focusInspection ? inspection.id : target.id)

        // Act
        let preset = PersonalDeskPreset(label: "Research", desk: desk)

        // Assert
        #expect(preset.boards.map(\.label) == [other.label, target.label])
        #expect(preset.focusedBoardIndex == 1)
    }
}
