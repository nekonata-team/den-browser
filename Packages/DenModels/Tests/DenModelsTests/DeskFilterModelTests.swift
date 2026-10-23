import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct DeskFilterModelTests {
    @Test func filteringMatchesBoardLabelAndCurrentSheetURLWithoutChangingFocus() {
        let alpha = board("Alpha", url: "https://search.example/")
        let bravo = board("Bravo", url: "https://github.com/example/repository")
        let charlie = board("Charlie", url: "https://docs.example/")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: bravo.id)
        let model = DeskFilterModel(focusedDesk: { source }, focusBoard: { _ in })

        model.enter()
        model.setQuery("char")

        #expect(model.filteredBoards.map(\.id) == [charlie.id])
        #expect(model.selectionBoardID == charlie.id)
        #expect(source.focusedBoardID == bravo.id)

        model.setQuery("github")

        #expect(model.filteredBoards.map(\.id) == [bravo.id])
        #expect(model.selectionBoardID == bravo.id)
        #expect(source.focusedBoardID == bravo.id)
    }

    @Test func selectionNavigationWrapsAtBothEnds() {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let charlie = board("Charlie")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: alpha.id)
        let model = DeskFilterModel(focusedDesk: { source }, focusBoard: { _ in })

        model.enter()

        model.selectBoard(by: -1)
        #expect(model.selectionBoardID == charlie.id)
        model.selectBoard(by: 1)
        #expect(model.selectionBoardID == alpha.id)
    }

    @Test(.timeLimit(.minutes(1)))
    func confirmingSelectionFocusesImmediatelyAndCentersAfterDismissal() async {
        let first = board("First")
        let selected = board("Selected")
        var source = desk("Desk", boards: [first, selected], focusedBoardID: first.id)
        let model = DeskFilterModel(
            focusedDesk: { source }, focusBoard: { source.focusedBoardID = $0 })
        let (centering, continuation) = AsyncStream<Void>.makeStream()
        model.onCenterFocusedBoard = {
            continuation.yield(())
            continuation.finish()
        }
        model.enter()
        model.confirmQuery()

        model.confirmSelection(selected.id)

        #expect(!model.isPresented)
        #expect(source.focusedBoardID == selected.id)
        var iterator = centering.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }

    private func board(_ label: String, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: 520, currentSheetURL: URL(string: url))
    }

    private func desk(
        _ label: String,
        boards: [BoardState],
        focusedBoardID: BoardID?
    ) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }
}
