import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenWindowCompositionTests {
    @Test func constructionDoesNotConnectWindowEffects() {
        // Arrange
        let controller = DenController(state: .sample)
        controller.reportFeedback("Ready")

        // Act
        let composition = DenWindowComposition(controller: controller)

        // Assert
        #expect(controller.onWindowEffect == nil)
        #expect(composition.model.displayedFeedback == nil)
    }

    @Test func connectingDeliversCurrentFeedbackAndSynchronousWindowEffects() {
        // Arrange
        let controller = DenController(state: .sample)
        controller.reportFeedback("Ready")
        let composition = DenWindowComposition(controller: controller)
        defer { composition.disconnect() }

        // Act
        composition.connect()
        controller.onWindowEffect?(.presentOpenBoard(initialURL: nil, afterBoardID: nil))

        // Assert
        #expect(composition.model.displayedFeedback?.id == controller.latestFeedback?.id)
        #expect(composition.model.isOpenBoardPanelPresented)
    }

    @Test func disconnectingRemovesWindowEffectsAndEndsFeedbackPresentation() {
        // Arrange
        let controller = DenController(state: .sample)
        let composition = DenWindowComposition(controller: controller)
        composition.connect()
        controller.reportFeedback("Ready")

        // Act
        composition.disconnect()

        // Assert
        #expect(controller.onWindowEffect == nil)
        #expect(composition.model.displayedFeedback == nil)
    }
}
