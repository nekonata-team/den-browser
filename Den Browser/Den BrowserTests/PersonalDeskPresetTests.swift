import Testing

@testable import Den_Browser

@MainActor
struct PersonalDeskPresetTests {
    @Test(arguments: [false, true])
    func capturePreservesInspectionGroupAndFocusedBoard(focusInspection: Bool) throws {
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
        #expect(preset.boards.map(\.label) == [other.label, target.label, inspection.label])
        #expect(preset.boards.map(\.width) == [other.width, target.width, inspection.width])
        #expect(preset.boards[2].content == .inspection)
        #expect(preset.boards[2].targetBoardIndex == 1)
        #expect(preset.focusedBoardIndex == (focusInspection ? 2 : 1))

        let encoded = try JSONEncoder().encode(preset)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let boards = try #require(object["boards"] as? [[String: Any]])
        let inspectionContent = try #require(boards[2]["content"] as? [String: Any])
        #expect(boards[2]["targetBoardIndex"] as? Int == 1)
        #expect(inspectionContent["kind"] as? String == "inspection")
        #expect(inspectionContent.count == 1)
        #expect(try JSONDecoder().decode(PersonalDeskPreset.self, from: encoded) == preset)
    }

    @Test(arguments: [false, true])
    func captureOmitsTutorialBoardAndKeepsRemainingFocus(focusTutorial: Bool) throws {
        // Arrange
        let tutorial = BoardState(
            label: "Tutorial",
            width: 520,
            tutorial: TutorialBoardState())
        let target = BoardState(label: "Target", width: 520, currentSheetURL: nil)
        let inspection = BoardState(width: 360, targetBoardID: target.id)
        let desk = DeskState(
            label: "Research",
            boards: [tutorial, target, inspection],
            focusedBoardID: focusTutorial ? tutorial.id : inspection.id)

        // Act
        let preset = PersonalDeskPreset(label: "Research", desk: desk)

        // Assert
        #expect(preset.boards.map(\.label) == [target.label, inspection.label])
        let savedInspection = try #require(preset.boards.last)
        #expect(savedInspection.targetBoardIndex == 0)
        #expect(preset.focusedBoardIndex == (focusTutorial ? nil : 1))
    }

    @Test func decodesPreviouslySavedPresetWithoutInspectionMetadata() throws {
        // Arrange
        let data = Data(
            #"""
            {"id":"00000000-0000-0000-0000-000000000001","label":"Old","boards":[{"label":"Target","width":520,"content":{"kind":"web","initialSheetURL":"https://example.com/"}}],"focusedBoardIndex":0}
            """#.utf8)

        // Act
        let preset = try JSONDecoder().decode(PersonalDeskPreset.self, from: data)

        // Assert
        #expect(preset.label == "Old")
        #expect(preset.focusedBoardIndex == 0)
        #expect(preset.boards.count == 1)
        #expect(preset.boards[0].initialSheetURL == URL(string: "https://example.com/"))
        #expect(preset.boards[0].targetBoardIndex == nil)
    }
}
