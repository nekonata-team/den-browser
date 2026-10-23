import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenWindowCompositionTests {
    @Test func constructionDoesNotConnectWindowEffects() {
        // Arrange
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration())
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
            configuration: makeTestBoardRuntimeConfiguration())
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
            configuration: makeTestBoardRuntimeConfiguration())
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
