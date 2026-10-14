import DenDomain
import DenPresentationModels
import Foundation
import Testing

@MainActor
struct UniversalSearchModelTests {
    @Test func exactNavigationIDsPrecedeMetadataMatchesAndPreserveCreation() {
        // Arrange
        let search = UniversalSearchModel()
        let id = UUID()
        let query = id.uuidString.lowercased()
        let metadataMatch = UniversalSearchItem(
            target: .board(BoardID()), title: "Reference", detail: "Board", keywords: query)
        let board = UniversalSearchItem(target: .board(BoardID(id)), title: query, detail: "Board")
        let desk = UniversalSearchItem(target: .desk(DeskID(id)), title: "Work", detail: "Desk")
        let profile = UniversalSearchItem(target: .profile(ProfileID(id)), title: "Personal", detail: "Profile")
        let essential = UniversalSearchItem(target: .essential(id), title: "Docs", detail: "Essential")
        search.items = [metadataMatch, board, desk, profile, essential]

        // Act
        search.query = " \(query) "

        // Assert
        #expect(
            search.results.map(\.target) == [
                board.target, desk.target, profile.target, metadataMatch.target, .createBoard(query),
            ])
        #expect(search.selectedItem == board)
    }

    @Test(arguments: [false, true])
    func partialOrUnknownNavigationIDsDoNotMatch(useUnknownID: Bool) {
        // Arrange
        let search = UniversalSearchModel()
        let id = UUID()
        search.items = [
            UniversalSearchItem(target: .board(BoardID(id)), title: "Docs", detail: "Board"),
            UniversalSearchItem(target: .desk(DeskID(id)), title: "Work", detail: "Desk"),
            UniversalSearchItem(target: .profile(ProfileID(id)), title: "Personal", detail: "Profile"),
        ]
        let query = useUnknownID ? UUID().uuidString : String(id.uuidString.prefix(8))

        // Act
        search.query = query

        // Assert
        #expect(search.results.map(\.target) == [.createBoard(query)])
    }

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
