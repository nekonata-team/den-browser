import DenApplication
import DenDomain
import DenModels
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
                session: ProfileWindowSession(
                    resources: storage,
                    configuration: makeTestBoardRuntimeConfiguration(
                        websiteDataStore: .nonPersistent(), sheetNavigation: navigation, preferences: preferences),
                    presentedDeskID: deskID, canPresentDesk: { _ in true }, onDeskPresentationRequest: { _ in true },
                    onWillResetDen: {}))
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
        let sink = first.session.connection.onWindowEffect
        first.session.connection.onWindowEffect = { effect in
            if case .suppressBoardMutationAnimation = effect {
                #expect(storage.state.desks[0].boards.isEmpty)
                prepared = true
            }
            sink?(effect)
        }
        defer { first.session.connection.onWindowEffect = nil }

        // Act
        first.model.openBoard.submit("https://example.com", preferredWidth: 640)

        // Assert
        #expect(prepared)
        #expect(storage.state.desks[0].boards.first?.width == 640)
        #expect(storage.state.desks[1] == secondDesk)
        #expect(first.session.navigation.presentedDeskID == firstDesk.id)
        #expect(second.session.navigation.presentedDeskID == secondDesk.id)
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
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(boards: [anchor])),
                    onSave: { state in
                        #expect(state.desks.flatMap(\.boards).count == 2)
                        events.append("save")
                        return true
                    },
                    onRecentItemsSave: { _ in
                        events.append("recent")
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            // Act
            let result = session.boardOpening.requestOpenBoard(
                input: "https://example.com", afterBoardID: targetExists ? anchor.id : BoardID())

            // Assert
            #expect(session.resources.state.desks.flatMap(\.boards).count == (targetExists ? 2 : 1))
            #expect(session.resources.recentItems.count == (targetExists ? 1 : 0))
            #expect(events == (targetExists ? ["save"] : []))
            switch result {
            case .accepted: #expect(targetExists)
            case .rejected: #expect(!targetExists)
            }
        }
    }

    @Test func oversizedInputSavesInsertionWithoutRecent() {
        // Arrange
        var saveCount = 0
        let input = String(repeating: "x", count: BoardOpening.maximumPersistedRecentInputLength + 1)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()),
                    onSave: { _ in
                        saveCount += 1
                        return true
                    },
                    onRecentItemsSave: { _ in
                        Issue.record("Oversized input must not be recorded")
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            ({
                // Act
                let result = session.boardOpening.requestOpenBoard(input: input)

                // Assert
                guard case .accepted = result else {
                    Issue.record("Expected a Board to open")
                    return
                }
                #expect(session.resources.state.desks.flatMap(\.boards).count == 1)
                #expect(session.resources.recentItems.isEmpty)
                #expect(saveCount == 1)
            })()
        }
    }
}
