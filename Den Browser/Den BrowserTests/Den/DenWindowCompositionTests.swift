import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenWindowCompositionTests {
    @Test func constructionDoesNotConnectWindowEffects() {
        // Arrange
        let store = DenStore(state: .sample)
        store.reportFeedback("Ready")

        // Act
        let composition = DenWindowComposition(store: store)

        // Assert
        #expect(store.onWindowEffect == nil)
        #expect(composition.model.displayedFeedback == nil)
    }

    @Test func connectingDeliversCurrentFeedbackAndSynchronousWindowEffects() {
        // Arrange
        let store = DenStore(state: .sample)
        store.reportFeedback("Ready")
        let composition = DenWindowComposition(store: store)
        defer { composition.disconnect() }

        // Act
        composition.connect()
        store.onWindowEffect?(.presentOpenBoard(initialURL: nil, afterBoardID: nil))

        // Assert
        #expect(composition.model.displayedFeedback?.id == store.latestFeedback?.id)
        #expect(composition.model.isOpenBoardPanelPresented)
    }

    @Test func disconnectingRemovesWindowEffectsAndEndsFeedbackPresentation() {
        // Arrange
        let store = DenStore(state: .sample)
        let composition = DenWindowComposition(store: store)
        composition.connect()
        store.reportFeedback("Ready")

        // Act
        composition.disconnect()

        // Assert
        #expect(store.onWindowEffect == nil)
        #expect(composition.model.displayedFeedback == nil)
    }
}
