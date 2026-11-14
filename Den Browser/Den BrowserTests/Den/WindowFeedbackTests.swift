import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import Observation
import Synchronization
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct WindowFeedbackTests {
    @Test func restoreRecentlyRemovedBoardReportsFeedbackWhenNoneExists() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.boardRemoval.restoreRecentlyRemovedBoard()
        #expect(session.feedback.latest?.message == "No removed board to restore.")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func invalidDeskNumberReportsFeedback() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        session.boardNavigation.focusDesk(number: 5)
        #expect(session.feedback.latest?.message == "Desk 5 does not exist.")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func reportFeedbackSetsLatestFeedbackWithSeverity() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        #expect(session.feedback.latest == nil)

        session.context.feedback.publish("Test Toast", severity: .warning)

        #expect(session.feedback.latest?.message == "Test Toast")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func reportFeedbackPreservesTitleAndBody() {
        let session = ProfileWindowSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(.sample)),
            configuration: makeTestBoardRuntimeConfiguration()
        )

        session.context.feedback.publish(title: "Build", body: "Finished")

        #expect(session.feedback.latest?.title == "Build")
        #expect(session.feedback.latest?.body == "Finished")
        #expect(session.feedback.latest?.message == "Build: Finished")
    }

    @Test(arguments: [":zellij project", ":zmx", ":tutorial", "https://", ""])
    func openBoardPanelKeepsInvalidDrawerInput(input: String) {
        // Arrange
        let source = makeTestDesk("Desk")
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [source]))
            )
        ) { session, windowModel in
            windowModel.showOpenBoardPanel()
            windowModel.openBoard.input = input

            // Act
            windowModel.openBoard.submitToDrawer()

            // Assert
            #expect(windowModel.isOpenBoardPanelPresented)
            #expect(windowModel.openBoard.input == input)
            #expect(windowModel.openBoard.message != nil)
            #expect(session.resources.state.drawerItems.isEmpty)
            #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        }
    }

    @Test func openingBoardFeedbackTargetFocusesItsBoard() {
        let target = makeTestBoard("Target")
        let first = makeTestDesk("First")
        let second = makeTestDesk("Second", boards: [target])
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [first, second], focusedDeskID: first.id))
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.setTemporaryContext(.drawer)
        session.context.feedback.publish(title: "Build", body: "Finished", target: .board(target.id))
        session.notifications.openFeedbackTarget(session.feedback.latest?.target)

        #expect(session.navigation.presentedDeskID == second.id)
        #expect(session.navigation.focusedBoard?.id == target.id)
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func openingDrawerFeedbackTargetOpensAndExpandsItem() throws {
        let item = DrawerItem(url: try #require(URL(string: "https://example.com/")))
        let drawerDesk = makeTestDesk("Desk")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(
                        desks: [drawerDesk],
                        focusedDeskID: drawerDesk.id,
                        drawerItems: [item]
                    )
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.context.feedback.publish(
            title: nil,
            body: "Open item",
            target: DenFeedback.Target.drawerItem(item.id)
        )
        session.notifications.openFeedbackTarget(session.feedback.latest?.target)

        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.selectedItemID == item.id)
        #expect(windowModel.drawer.expandedItemID == item.id)
    }

    @Test func resetDenRequiresConfirmationBeforeChangingState() {
        let board = makeTestBoard("Board")
        let populated = makeTestDesk("Populated", boards: [board])
        var savedState: DenState?
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [populated], focusedDeskID: populated.id)),
                onSave: { state in
                    let callback: (DenState) -> Void = { savedState = $0 }
                    callback(state)
                    return true
                }
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let originalState = session.resources.state

        windowModel.requestResetDenConfirmation()

        #expect(windowModel.isResetDenPending)
        #expect(session.resources.state == originalState)
        #expect(savedState == nil)

        windowModel.cancelResetDen()

        #expect(!windowModel.isResetDenPending)
        #expect(session.resources.state == originalState)
        #expect(savedState == nil)
    }

    @Test func latestConfirmationReplacesEarlierRequestAndCanBeCancelled() {
        let board = makeTestBoard("Board")
        let populated = makeTestDesk("Populated", boards: [board])
        let empty = makeTestDesk("Empty")
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [populated, empty], focusedDeskID: populated.id)
                )
            ),
            configuration: makeTestBoardRuntimeConfiguration()
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        session.desks.deleteFocusedDesk()
        if case let .deleteDesk(pending)? = windowModel.pendingConfirmation {
            #expect(pending.id == populated.id)
        } else {
            Issue.record("Expected a desk deletion confirmation")
        }

        windowModel.requestResetDenConfirmation()
        #expect(windowModel.isResetDenPending)

        windowModel.cancelResetDen()
        #expect(!windowModel.hasPendingConfirmation)
    }

    @Test(arguments: [false, true])
    func essentialReplacementRequiresConfirmationAndPreservesIdentity(confirm: Bool) throws {
        try withTestSession(
            resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState()))
        ) { session in
            do {
                let denWindowComposition = DenWindowComposition(session: session)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                // Arrange
                #expect(
                    session.essentials.saveEssential(
                        name: "Original",
                        key: "e",
                        input: "https://example.com/original"
                    )
                )
                #expect(
                    session.essentials.saveEssential(
                        name: "Other",
                        key: "E",
                        input: "https://example.com/other"
                    )
                )
                let original = session.configuration.preferences.essentials
                let draft = SaveEssentialDraft(
                    name: "Updated",
                    key: "e",
                    input: "https://example.com/updated"
                )
                windowModel.showSaveEssentialPanel(
                    name: draft.name,
                    key: draft.key,
                    input: draft.input
                )
                #expect(
                    windowModel.saveEssential(
                        name: draft.name,
                        key: draft.key,
                        input: draft.input
                    )
                )

                // Act
                if confirm {
                    windowModel.confirmEssentialReplacement()
                } else {
                    windowModel.cancelEssentialReplacement()
                }

                // Assert
                #expect(windowModel.pendingConfirmation == nil)
                #expect(windowModel.isSaveEssentialPanelPresented == !confirm)
                #expect(
                    session.configuration.preferences.essentials.map(\.id)
                        == original.map(\.id)
                )
                #expect(session.configuration.preferences.essentials.last == original.last)
                if confirm {
                    let replaced = try #require(
                        session.configuration.preferences.essentials.first
                    )
                    #expect(replaced.name == draft.name)
                    #expect(replaced.key == draft.key)
                    #expect(replaced.input == draft.input)
                } else {
                    #expect(session.configuration.preferences.essentials == original)
                    #expect(windowModel.saveEssentialDraft == draft)
                }
            }
        }
    }

    @Test func openFeedbackTargetCentersBoardEvenWhenAlreadyFocused() {
        let targetBoard = makeTestBoard("Target")
        var currentDesk = makeTestDesk("Main", boards: [targetBoard], focusedBoardID: targetBoard.id)
        currentDesk.scrollOffsetX = 180
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [currentDesk]))
            )
        ) { session, windowModel in
            let initialCenterRequests = windowModel.centerFocusedBoardRequest

            // Act
            session.notifications.openFeedbackTarget(.board(targetBoard.id))

            // Assert
            #expect(windowModel.centerFocusedBoardRequest == initialCenterRequests + 1)
            #expect(session.navigation.focusedDesk?.scrollOffsetX == nil)
        }
    }

    @Test func openFeedbackTargetDoesNotScrollWindowWhenTargetIsPresentedElsewhere() {
        let sourceBoard = makeTestBoard("Source")
        let targetBoard = makeTestBoard("Target")
        var sourceDesk = makeTestDesk("Source", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
        sourceDesk.scrollOffsetX = 180
        let targetDesk = makeTestDesk("Target", boards: [targetBoard], focusedBoardID: targetBoard.id)
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [sourceDesk, targetDesk]))
            )
        ) { session, _ in
            let existingSession = session

            let session = ProfileWindowSession(
                resources: existingSession.resources,
                configuration: makeTestBoardRuntimeConfiguration(
                    websiteDataStore: .nonPersistent(),
                    sheetNavigation: existingSession.configuration.sheetNavigation,
                    preferences: existingSession.configuration.preferences
                ),
                presentedDeskID: sourceDesk.id,
                canPresentDesk: { _ in false },
                onDeskPresentationRequest: { _ in false },
                onWillResetDen: {}
            )

            session.notifications.openFeedbackTarget(.board(targetBoard.id))

            #expect(session.navigation.presentedDeskID == sourceDesk.id)
            #expect(session.navigation.focusedDesk?.scrollOffsetX == 180)
        }
    }
}
