import DenDomain
import DenModels
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
        search.recentItems = [.search("zen")]

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
        search.query = "Desk"
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
    @Test(arguments: [0, 12])
    func emptySearchShowsRecentEssentialsThenOtherKinds(recentCount: Int) {
        // Arrange
        let search = UniversalSearchModel()
        let firstBoard = UniversalSearchItem(target: .board(BoardID()), title: "First", detail: "Board · First Desk")
        let secondBoard = UniversalSearchItem(target: .board(BoardID()), title: "Second", detail: "Board · Second Desk")
        let essential = UniversalSearchItem(target: .essential(UUID()), title: "Docs", detail: "Essential")
        let desk = UniversalSearchItem(target: .desk(DeskID()), title: "Work", detail: "Desk")
        let profile = UniversalSearchItem(target: .profile(ProfileID()), title: "Personal", detail: "Profile")
        let command = UniversalSearchItem(target: .command(.openSettings), title: "Open Settings", detail: "Command")
        search.items = [firstBoard, secondBoard, essential, desk, profile, command]
        search.recentItems = (0..<recentCount).map { .search("query \($0)") }

        // Act
        let targets = search.results.map(\.target)

        // Assert
        #expect(
            targets == search.recentItems.prefix(5).map { .recent($0) }
                + [
                    essential.target, firstBoard.target, secondBoard.target, desk.target, profile.target,
                    command.target,
                ])
    }

    @Test func recentSearchFindsOlderMatchesAndPrioritizesExactMatchesWithoutHidingOtherTargets() {
        // Arrange
        let search = UniversalSearchModel()
        let desk = UniversalSearchItem(target: .desk(DeskID()), title: "Docs", detail: "Desk")
        let exact = RecentItem.search("docs")
        let titled = RecentItem.url(URL(string: "https://example.com/old")!, title: "Docs guide")
        search.items = [desk]
        search.recentItems = (0..<498).map { .search("docs \($0)") } + [exact, titled]

        // Act
        search.query = "DOCS"
        let targets = search.results.map(\.target)

        // Assert
        #expect(targets.first == desk.target)
        #expect(targets[1] == .recent(exact))
        #expect(targets.filter { if case .recent = $0 { true } else { false } }.count == 5)
        #expect(targets.last == .createBoard("DOCS"))
    }

    @Test func recentSearchMatchesTermsAcrossTitleAndInput() {
        // Arrange
        let search = UniversalSearchModel()
        let item = RecentItem.url(URL(string: "https://example.com/reference")!, title: "Swift guide")
        search.recentItems = [.search("unrelated"), item]

        // Act
        search.query = "SWIFT reference"

        // Assert
        #expect(search.results.first?.target == .recent(item))
    }
}
