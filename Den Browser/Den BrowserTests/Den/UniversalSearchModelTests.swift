import DenDomain
import DenPresentationModels
import Foundation
import Testing

@MainActor
struct UniversalSearchModelTests {
    @Test func commandPrefixExcludesNavigationAndCreation() {
        // Arrange
        let search = UniversalSearchModel()
        let command = UniversalSearchItem(target: .command(.toggleZenView), title: "Toggle Zen View", detail: "Command")
        search.items = [
            UniversalSearchItem(target: .board(BoardID()), title: "Zen", detail: "Switch to Board"), command,
        ]

        // Act
        search.query = "> zen"

        // Assert
        #expect(search.results == [command])
    }

    @Test func sameNameBoardAndEssentialRemainDistinctActions() {
        // Arrange
        let search = UniversalSearchModel()
        let boardID = BoardID()
        let essentialID = UUID()
        search.items = [
            UniversalSearchItem(target: .board(boardID), title: "GitHub", detail: "Switch to Board"),
            UniversalSearchItem(
                target: .essential(essentialID), title: "GitHub", detail: "Create Board from Essential"),
        ]

        // Act
        search.query = "github"

        // Assert
        #expect(search.results.map(\.target) == [.board(boardID), .essential(essentialID), .createBoard("github")])
    }

    @Test func removedSelectionFallsBackToAvailableResult() {
        // Arrange
        let search = UniversalSearchModel()
        let first = UniversalSearchItem(target: .desk(DeskID()), title: "First", detail: "Desk")
        let second = UniversalSearchItem(target: .desk(DeskID()), title: "Second", detail: "Desk")
        search.items = [first, second]
        search.moveSelection(by: 1)
        #expect(search.selectedItem == second)

        // Act
        search.items = [first]

        // Assert
        #expect(search.selectedItem == first)
    }

    @Test func queryMatchesAllTermsAcrossMetadata() {
        // Arrange
        let search = UniversalSearchModel()
        let item = UniversalSearchItem(
            target: .board(BoardID()), title: "Design", detail: "Work / Planning", keywords: "https://example.com")
        search.items = [item]

        // Act
        search.query = "design EXAMPLE"

        // Assert
        #expect(search.results.first == item)
        #expect(search.results.last?.target == .createBoard("design EXAMPLE"))
    }
}
