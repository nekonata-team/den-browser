import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenViewModelTests {
    @Test(arguments: [false, true])
    func runtimeFocusSelectsWebBoardButDoesNotStealFocusForTerminal(isTerminal: Bool) {
        // Arrange
        let current = BoardState(label: "Current", width: 520, currentSheetURL: URL(string: "https://current.example/"))
        let target =
            isTerminal
            ? BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
            : BoardState(label: "Web", width: 520, currentSheetURL: URL(string: "https://target.example/"))
        let desk = DeskState(label: "Desk", boards: [current, target], focusedBoardID: current.id)
        let store = DenStore(state: DenState(desks: [desk], focusedDeskID: desk.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        // Act
        store.onWindowEffect?(.runtimeFocusedBoard(target.id))

        // Assert
        #expect(store.focusedBoard?.id == (isTerminal ? current.id : target.id))
    }

    @Test func latestFeedbackIsDisplayedAndPreviousTimerCannotDismissReplacement() async {
        // Arrange
        let store = DenStore(state: .sample)
        let viewModel = DenViewModel(store: store, feedbackDuration: .milliseconds(150))
        viewModel.connect()
        defer { viewModel.disconnect() }

        // Act
        store.reportFeedback("First")
        try? await Task.sleep(for: .milliseconds(100))
        store.reportFeedback("Latest")
        try? await Task.sleep(for: .milliseconds(70))

        // Assert
        #expect(viewModel.displayedFeedback?.body == "Latest")

        try? await Task.sleep(for: .milliseconds(110))
        #expect(viewModel.displayedFeedback == nil)
    }

    @Test func receivingSameFeedbackAgainDoesNotRedisplayAfterDismissal() {
        // Arrange
        let store = DenStore(state: .sample)
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        let feedback = DenFeedback(body: "Saved")

        // Act
        viewModel.receive(.feedback(feedback))
        viewModel.dismissFeedback()
        viewModel.receive(.feedback(feedback))

        // Assert
        #expect(viewModel.displayedFeedback == nil)
    }

    @Test func tappingFeedbackOpensTargetAndDismissesIt() throws {
        // Arrange
        let board = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let first = DeskState(label: "Empty", boards: [])
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(
            state: DenState(desks: [first, desk], focusedDeskID: first.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        store.reportFeedback(title: "Build", body: "Finished", target: .board(board.id))
        let feedback = try #require(viewModel.displayedFeedback)

        // Act
        viewModel.handleTap(on: feedback)

        // Assert
        #expect(store.focusedBoard?.id == board.id)
        #expect(viewModel.temporaryContext == nil)
        #expect(viewModel.displayedFeedback == nil)
    }

    @Test func tappingUntargetedFeedbackDismissesItWithoutChangingState() throws {
        // Arrange
        let store = DenStore(state: .sample)
        let initialState = store.state
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        store.reportFeedback("Saved")
        let feedback = try #require(viewModel.displayedFeedback)

        // Act
        viewModel.handleTap(on: feedback)

        // Assert
        #expect(viewModel.displayedFeedback == nil)
        #expect(store.state == initialState)
    }
}
