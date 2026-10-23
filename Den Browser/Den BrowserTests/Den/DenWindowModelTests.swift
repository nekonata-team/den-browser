import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import Observation
import Synchronization
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenWindowModelTests {
    @Test(arguments: [false, true])
    func runtimeFocusSelectsWebBoardButDoesNotStealFocusForTerminal(isTerminal: Bool) {
        // Arrange
        let current = BoardState(label: "Current", width: 520, currentSheetURL: URL(string: "https://current.example/"))
        let target =
            isTerminal
            ? BoardState(label: "Terminal", width: 520, workingDirectory: "/tmp")
            : BoardState(label: "Web", width: 520, currentSheetURL: URL(string: "https://target.example/"))
        let desk = DeskState(label: "Desk", boards: [current, target], focusedBoardID: current.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }

        // Act
        session.connection.onWindowEffect?(.runtimeFocusedBoard(target.id))

        // Assert
        #expect(session.navigation.focusedBoard?.id == (isTerminal ? current.id : target.id))
    }

    @Test func deletionInAnotherWindowInvalidatesSelectionAndInsertionReferences() {
        // Arrange
        let board = BoardState(label: "Board", width: 520, currentSheetURL: URL(string: "https://board.example/"))
        let selectedBoard =
            BoardState(label: "Selected", width: 520, currentSheetURL: URL(string: "https://selected.example/"))
        let mainDesk = DeskState(label: "Main", boards: [board], focusedBoardID: board.id)
        let selectedDesk = DeskState(label: "Selected", boards: [selectedBoard], focusedBoardID: selectedBoard.id)
        let otherDesk = DeskState(label: "Other", boards: [])
        let storage = DenProfileResources(
            state: DenState(desks: [mainDesk, selectedDesk, otherDesk], focusedDeskID: mainDesk.id))
        let defaults = makeTestDefaults()
        let pasteboard = NSPasteboard.withUniqueName()
        let sheetNavigation = SheetNavigationManager(
            defaults: defaults, pasteboard: pasteboard, scriptSource: "")
        let preferences = AppPreferences(defaults: defaults)
        func makeSession(presenting deskID: DeskID) -> ProfileWindowSession {
            ProfileWindowSession(
                resources: storage,
                configuration: makeTestBoardRuntimeConfiguration(
                    websiteDataStore: .nonPersistent(), sheetNavigation: sheetNavigation, preferences: preferences),
                pasteboard: pasteboard, presentedDeskID: deskID, canPresentDesk: { _ in true },
                onDeskPresentationRequest: { _ in true }, onWillResetDen: {})
        }
        let deletingSession = makeSession(presenting: mainDesk.id)
        let otherWindowComposition = DenWindowComposition(session: makeSession(presenting: otherDesk.id))
        let otherWindow = otherWindowComposition.model
        otherWindowComposition.connect()
        defer { otherWindowComposition.disconnect() }
        otherWindow.overview.preparePresentation(deskID: mainDesk.id, boardID: board.id)
        otherWindow.openBoard.preparePresentation(afterBoardID: board.id)

        // Act - another window removes the Board.
        deletingSession.boardRemoval.removeBoard(board.id)

        // Assert
        #expect(otherWindow.overview.selectionBoardID == nil)
        #expect(otherWindow.openBoard.afterBoardID == nil)

        // Act - another window removes the Desk currently selected in Overview.
        otherWindow.overview.preparePresentation(deskID: selectedDesk.id, boardID: selectedBoard.id)
        deletingSession.desks.confirmDeskDeletion(selectedDesk.id)

        // Assert
        #expect(otherWindow.overview.selectionDeskID == nil)
        #expect(otherWindow.overview.selectionBoardID == nil)
    }

    @Test func latestFeedbackIsDisplayedAndPreviousTimerCannotDismissReplacement() async {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session, feedbackDuration: .milliseconds(30))
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        // Act
        session.context.feedback.publish("First")
        try? await Task.sleep(for: .milliseconds(20))
        session.context.feedback.publish("Latest")
        try? await Task.sleep(for: .milliseconds(15))

        // Assert
        #expect(windowModel.displayedFeedback?.body == "Latest")

        let dismissDeadline = ContinuousClock.now + .seconds(2)
        while windowModel.displayedFeedback != nil, ContinuousClock.now < dismissDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(windowModel.displayedFeedback == nil)
    }

    @Test func receivingSameFeedbackAgainDoesNotRedisplayAfterDismissal() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let feedback = DenFeedback(body: "Saved")

        // Act
        windowModel.receive(.feedback(feedback))
        windowModel.dismissFeedback()
        windowModel.receive(.feedback(feedback))

        // Assert
        #expect(windowModel.displayedFeedback == nil)
    }

    @Test func tappingFeedbackOpensTargetAndDismissesIt() throws {
        // Arrange
        let board = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let first = DeskState(label: "Empty", boards: [])
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, desk], focusedDeskID: first.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.context.feedback.publish(title: "Build", body: "Finished", target: .board(board.id))
        let feedback = try #require(windowModel.displayedFeedback)

        // Act
        windowModel.handleTap(on: feedback)

        // Assert
        #expect(session.navigation.focusedBoard?.id == board.id)
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.displayedFeedback == nil)
    }

    @Test func tappingUntargetedFeedbackDismissesItWithoutChangingState() throws {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
        let initialState = session.resources.state
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.context.feedback.publish("Saved")
        let feedback = try #require(windowModel.displayedFeedback)

        // Act
        windowModel.handleTap(on: feedback)

        // Assert
        #expect(windowModel.displayedFeedback == nil)
        #expect(session.resources.state == initialState)
    }
}
