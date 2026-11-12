import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenWindowCompositionTests {
    @Test func leavingDenModeRestoresThePendingBoardSourceSynchronously() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.configuration.preferences.setRememberBoardInputMethod(true)
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        let tracker = session.inputSourceTracker
        var selected: [String] = []
        tracker.readInputSource = { "english" }
        tracker.restoreInputSource = { selected.append($0) }
        composition.model.isDenMode = true
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)
        tracker.boardDidFocus(board, isEnabled: true)
        #expect(selected.isEmpty)

        // Act
        composition.model.exitDenMode()

        // Assert
        #expect(selected == ["japanese"])
    }

    @Test func sheetInputRestoresThePendingSourceBeforeForwarding() throws {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.configuration.preferences.setRememberBoardInputMethod(true)
        let composition = DenWindowComposition(session: session)
        composition.connect()
        defer { composition.disconnect() }
        let tracker = session.inputSourceTracker
        var selected: [String] = []
        tracker.readInputSource = { "english" }
        tracker.restoreInputSource = { selected.append($0) }
        tracker.isHandlingKeyboardAction = true
        let board = BoardID()
        tracker.setLastInputSource("japanese", for: board)
        tracker.boardDidFocus(board, isEnabled: true)
        tracker.isHandlingKeyboardAction = false
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "a",
                charactersIgnoringModifiers: "a",
                isARepeat: false,
                keyCode: 0
            )
        )

        // Act
        let consumed = KeyboardController.handle(event, session: session, windowModel: composition.model)

        // Assert
        #expect(!consumed)
        #expect(selected == ["japanese"])
    }

    @Test func constructionDoesNotConnectWindowEffects() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.context.feedback.publish("Ready")

        // Act
        let composition = DenWindowComposition(session: session)

        // Assert
        #expect(session.connection.onWindowEffect == nil)
        #expect(composition.model.displayedFeedback == nil)
    }

    @Test func connectingDeliversCurrentFeedbackAndSynchronousWindowEffects() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.context.feedback.publish("Ready")
        let composition = DenWindowComposition(session: session)
        defer { composition.disconnect() }

        // Act
        composition.connect()
        session.connection.onWindowEffect?(.presentOpenBoard(initialURL: nil, afterBoardID: nil))

        // Assert
        #expect(composition.model.displayedFeedback?.id == session.feedback.latest?.id)
        #expect(composition.model.isOpenBoardPanelPresented)
    }

    @Test func disconnectingRemovesWindowEffectsAndEndsFeedbackPresentation() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        composition.connect()
        session.context.feedback.publish("Ready")

        // Act
        composition.disconnect()

        // Assert
        #expect(session.connection.onWindowEffect == nil)
        #expect(composition.model.displayedFeedback == nil)
    }
}
