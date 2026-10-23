import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct UniversalSearchActionsTests {
    @Test func switchingToBoardDoesNotCreateOrDuplicateIt() {
        // Arrange
        let target = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let initial = BoardState(label: "First", width: 520, currentSheetURL: URL(string: "https://example.org/"))
        let first = DeskState(label: "First", boards: [initial], focusedBoardID: initial.id)
        let second = DeskState(label: "Second", boards: [target], focusedBoardID: target.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            model.isDenMode = true
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .board(target.id), session: session, windowModel: model,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error == nil)
            #expect(session.navigation.focusedBoard?.id == target.id)
            #expect(session.resources.state.desks.flatMap(\.boards).count == 2)
            #expect(model.temporaryContext == nil)
            #expect(!model.isDenMode)
        }
    }

    @Test func essentialCreatesBoardEvenWhenMatchingBoardExists() throws {
        // Arrange
        let input = "https://example.com/"
        let existing = BoardState(label: "Existing", width: 520, currentSheetURL: URL(string: input))
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            #expect(session.essentials.saveEssential(name: "Example", key: "e", input: input))
            let essential = try #require(session.configuration.preferences.essentials.first)
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .essential(essential.id), session: session, windowModel: model,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error == nil)
            #expect(session.navigation.focusedDesk?.boards.count == 2)
            #expect(session.navigation.focusedBoard?.id != existing.id)
            #expect(session.navigation.focusedBoard?.currentSheetURL?.absoluteString == input)
            #expect(model.temporaryContext == nil)
        }
    }

    @Test func rejectedCreationKeepsPaletteAndDoesNotChangeBoards() {
        // Arrange
        let existing = BoardState(label: "Existing", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .createBoard("unsupported://example"), session: session, windowModel: model,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error != nil)
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [existing.id])
            #expect(model.temporaryContext == .universalSearch)
        }
    }
    @Test(arguments: [false, true])
    func webInputOpensInDrawerWithoutCreatingBoard(fromEssential: Bool) throws {
        // Arrange
        let existing = BoardState(
            label: "Existing", width: 520, currentSheetURL: URL(string: "https://existing.example/"))
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            let input = "Swift concurrency"
            let essential = Essential(name: "Search", key: "s", input: input)
            #expect(session.configuration.preferences.setEssentials([essential]))
            model.showUniversalSearch()
            let target: UniversalSearchItem.Target =
                fromEssential ? .essential(essential.id) : .createBoard(input)

            // Act
            let error = UniversalSearchActions.perform(
                target, session: session, windowModel: model, inDrawer: true,
                openProfile: { _ in false }, openSettings: {})

            // Assert
            #expect(error == nil)
            let item = try #require(session.resources.state.drawerItems.first)
            #expect(
                item.url
                    == BoardInputResolver.normalizedURL(
                        from: input, searchEngine: session.configuration.preferences.searchEngine))
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [existing.id])
            #expect(model.isDrawerOpen)
            #expect(model.drawer.expandedItemID == item.id)
        }
    }

    @Test(arguments: [
        UniversalSearchItem.Target.createBoard(":terminal"), .desk(DeskID()), .profile(ProfileID()),
        .board(BoardID()), .command(.toggleZenView),
    ])
    func drawerSubmissionRejectsCommandsAndNavigation(target: UniversalSearchItem.Target) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            ({
                model.showUniversalSearch()
                var openedProfile = false
                var openedSettings = false

                // Act
                let error = UniversalSearchActions.perform(
                    target, session: session, windowModel: model, inDrawer: true,
                    openProfile: { _ in
                        openedProfile = true
                        return true
                    }, openSettings: { openedSettings = true })

                // Assert
                #expect(error != nil)
                #expect(model.temporaryContext == .universalSearch)
                #expect(session.resources.state.drawerItems.isEmpty)
                #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
                #expect(!model.isZenViewPresented)
                #expect(!openedProfile)
                #expect(!openedSettings)
            })()
        }
    }
    @Test func recentCreatesAnotherBoardAndMovesInputToFront() {
        // Arrange
        let item = RecentItem.url(URL(string: "https://example.com/")!)
        let existing = BoardState(label: "Example", width: 520, currentSheetURL: URL(string: item.displayText))
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(boards: [existing])),
                    recentItems: [.search("other"), item]),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            do {
                let denWindowSession = session
                let denWindowComposition = DenWindowComposition(session: denWindowSession)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let model = denWindowComposition.model
                let session = denWindowSession

                model.showUniversalSearch()

                // Act
                let error = UniversalSearchActions.perform(
                    .recent(item), session: session, windowModel: model,
                    openProfile: { _ in false }, openSettings: {})

                // Assert
                #expect(error == nil)
                #expect(session.navigation.focusedDesk?.boards.count == 2)
                #expect(session.navigation.focusedBoard?.id != existing.id)
                #expect(
                    session.navigation.focusedBoard?.currentSheetURL?.absoluteString
                        == item.displayText)
                #expect(session.resources.recentItems.first == item)
                #expect(model.temporaryContext == nil)
            }
        }
    }
}
