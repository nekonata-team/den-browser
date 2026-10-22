import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct BoardOpeningIntegrationTests {
    @Test func sharedCreationPreparesAndUpdatesOnlyTheInvokingWindow() {
        // Arrange
        let firstDesk = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let secondDesk = DeskState(label: "Second", boards: [], focusedBoardID: nil)
        let storage = DenProfileResources(state: DenState(desks: [firstDesk, secondDesk], focusedDeskID: firstDesk.id))
        let defaults = makeTestDefaults()
        let navigation = makeTestSheetNavigationManager(defaults: defaults, scriptSource: "")
        let preferences = AppPreferences(defaults: defaults)
        func window(_ deskID: DeskID) -> DenWindowComposition {
            DenWindowComposition(
                controller: DenController(
                    storage: storage, presentedDeskID: deskID, websiteDataStore: .nonPersistent(),
                    sheetNavigation: navigation, preferences: preferences,
                    canPresentDesk: { _ in true }, onDeskPresentationRequest: { _ in true }, onWillResetDen: {}))
        }
        let first = window(firstDesk.id)
        let second = window(secondDesk.id)
        first.connect()
        second.connect()
        defer {
            first.disconnect()
            second.disconnect()
        }
        first.model.showOpenBoardPanel()
        second.model.showOpenBoardPanel()
        first.model.isDenMode = true
        second.model.isDenMode = true
        var prepared = false
        let sink = first.controller.onWindowEffect
        first.controller.onWindowEffect = { effect in
            if case .suppressBoardMutationAnimation = effect {
                #expect(storage.state.desks[0].boards.isEmpty)
                prepared = true
            }
            sink?(effect)
        }
        defer { first.controller.onWindowEffect = nil }

        // Act
        first.model.openBoard.submit("https://example.com", preferredWidth: 640)

        // Assert
        #expect(prepared)
        #expect(storage.state.desks[0].boards.first?.width == 640)
        #expect(storage.state.desks[1] == secondDesk)
        #expect(first.controller.presentedDeskID == firstDesk.id)
        #expect(second.controller.presentedDeskID == secondDesk.id)
        #expect(!first.model.isOpenBoardPanelPresented)
        #expect(!first.model.isDenMode)
        #expect(second.model.isOpenBoardPanelPresented)
        #expect(second.model.isDenMode)
    }

    @Test(arguments: [true, false])
    func recentAndPersistenceFollowSuccessfulInsertion(targetExists: Bool) {
        // Arrange
        let anchor = BoardState(label: "Anchor", width: 520, workingDirectory: "/tmp")
        var events: [String] = []
        withTestController(
            boards: [anchor],
            onRecentItemsSave: { _ in
                events.append("recent")
                return true
            },
            onSave: { state in
                #expect(state.desks.flatMap(\.boards).count == 2)
                events.append("save")
                return true
            },
            body: { controller in
                // Act
                let result = controller.requestOpenBoard(
                    input: "https://example.com", afterBoardID: targetExists ? anchor.id : BoardID())

                // Assert
                #expect(controller.state.desks.flatMap(\.boards).count == (targetExists ? 2 : 1))
                #expect(controller.recentItems.count == (targetExists ? 1 : 0))
                #expect(events == (targetExists ? ["save"] : []))
                switch result {
                case .accepted: #expect(targetExists)
                case .rejected: #expect(!targetExists)
                }
            })
    }

    @Test func oversizedInputSavesInsertionWithoutRecent() {
        // Arrange
        var saveCount = 0
        let input = String(repeating: "x", count: BoardOpening.maximumPersistedRecentInputLength + 1)
        withTestController(
            onRecentItemsSave: { _ in
                Issue.record("Oversized input must not be recorded")
                return true
            },
            onSave: { _ in
                saveCount += 1
                return true
            },
            body: { controller in
                // Act
                let result = controller.requestOpenBoard(input: input)

                // Assert
                guard case .accepted = result else {
                    Issue.record("Expected a Board to open")
                    return
                }
                #expect(controller.state.desks.flatMap(\.boards).count == 1)
                #expect(controller.recentItems.isEmpty)
                #expect(saveCount == 1)
            })
    }
}
