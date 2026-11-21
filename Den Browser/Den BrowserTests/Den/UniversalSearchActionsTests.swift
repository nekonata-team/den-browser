import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import SwiftUI
import Testing

@testable import Den_Browser

@MainActor
struct UniversalSearchActionsTests {
    @Test func shortcutsCommandOpensGuideFromSearch() throws {
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        let resources = DenProfileResources(state: makeNativeTestState(desks: [desk]))
        try withTestWindow(resources: resources) { session, model in
            model.showUniversalSearch(commandsOnly: true)
            let items = UniversalSearch.sourceItems(
                state: session.resources.state,
                essentials: [],
                hasBoardUndoHistory: false,
                profiles: [],
                profileName: "Test"
            )
            let results = UniversalSearch.results(query: "> shortcuts", items: items, recentItems: [])
            let target = try #require(results.first?.target)
            #expect(target == .command(.showKeyboardShortcuts))
            let error = UniversalSearchActions.perform(
                target,
                session: session,
                windowModel: model,
                openProfile: { _ in false },
                openSettings: {}
            )
            #expect(error == nil)
            #expect(model.temporaryContext == .keyboardShortcuts)
        }
    }

    @Test func profileShortcutHintDisappearsWhenBindingIsReassigned() throws {
        let preferences = try makeKeyboardTestPreferences()
        let original = ShortcutConfiguration(preferences: preferences)
        let hint = try #require(UniversalSearchActions.shortcut(for: .openProfile, configuration: original))
        #expect(!hint.denModeOnly)
        let menuShortcut = try #require(ShortcutBinding.openProfile.characterKeyboardShortcut)
        #expect(menuShortcut.key.character == "p")
        #expect(menuShortcut.modifiers == [.control, .command])
        #expect(hint.binding == .openProfile)
        #expect(preferences.setShortcut(hint.binding, for: .toggleBoardRail) == nil)
        let updated = ShortcutConfiguration(preferences: preferences)
        #expect(UniversalSearchActions.shortcut(for: .openProfile, configuration: updated) == nil)
    }

    @Test func switchingToBoardDoesNotCreateOrDuplicateIt() {
        // Arrange
        let target = BoardState(label: "Target", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let initial = BoardState(label: "First", width: 520, currentSheetURL: URL(string: "https://example.org/"))
        let first = DeskState(label: "First", boards: [initial], focusedBoardID: initial.id)
        let second = DeskState(label: "Second", boards: [target], focusedBoardID: target.id)
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [first, second]))
            )
        ) { session, model in
            model.isDenMode = true
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .board(target.id),
                session: session,
                windowModel: model,
                openProfile: { _ in false },
                openSettings: {}
            )

            // Assert
            #expect(error == nil)
            #expect(session.navigation.focusedBoard?.id == target.id)
            #expect(session.resources.state.desks.flatMap(\.boards).count == 2)
            #expect(model.temporaryContext == nil)
            #expect(!model.isDenMode)
        }
    }

    @Test(arguments: [false, true])
    func drawerItemSearchOpensExistingPeekWithoutCreatingBoard(expired: Bool) throws {
        let url = try #require(URL(string: "https://example.com/draft"))
        var item = DrawerItem(url: url, title: "Notes")
        if expired { item.touchedAt = .distantPast }
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        withTestWindow(
            resources: DenProfileResources(
                state: DenState(desks: [desk], focusedDeskID: desk.id, drawerItems: [item])
            )
        ) { session, model in
            model.isDenMode = true
            model.showUniversalSearch()
            session.configuration.preferences.setDrawerAutoCleanup(expired)
            let items = UniversalSearch.sourceItems(
                state: session.resources.state,
                essentials: [],
                hasBoardUndoHistory: false,
                profiles: [],
                profileName: "Test",
                drawerItems: session.resources.state.drawerItems
            )
            let query = "notes draft"
            let target = UniversalSearchItem.Target.drawerItem(item.id)
            let results = UniversalSearch.results(query: query, items: items, recentItems: [])
            #expect(results.first?.target == target)
            let commands = UniversalSearch.results(query: "> draft", items: items, recentItems: [])
            #expect(!commands.contains { $0.target == target })

            let error = UniversalSearchActions.perform(
                target,
                session: session,
                windowModel: model,
                openProfile: { _ in false },
                openSettings: {}
            )

            if expired {
                #expect(error != nil)
                #expect(model.temporaryContext == .universalSearch)
                #expect(model.drawer.expandedItemID == nil)
            } else {
                #expect(error == nil)
                #expect(model.temporaryContext == .drawer)
                #expect(model.drawer.expandedItemID == item.id)
                #expect(!model.isDenMode)
                #expect(session.resources.state.drawerItems.map(\.id) == [item.id])
            }
            #expect(session.resources.state.desks.flatMap(\.boards).isEmpty)
        }
    }

    @Test func essentialCreatesBoardEvenWhenMatchingBoardExists() throws {
        // Arrange
        let input = "https://example.com/"
        let existing = BoardState(label: "Existing", width: 520, currentSheetURL: URL(string: input))
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))
            )
        ) { session, model in
            #expect(session.essentials.saveEssential(name: "Example", key: "e", input: input))
            let essential = try #require(session.configuration.preferences.essentials.first)
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .essential(essential.id),
                session: session,
                windowModel: model,
                openProfile: { _ in false },
                openSettings: {}
            )

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
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))
            )
        ) { session, model in
            model.showUniversalSearch()

            // Act
            let error = UniversalSearchActions.perform(
                .createBoard("unsupported://example"),
                session: session,
                windowModel: model,
                openProfile: { _ in false },
                openSettings: {}
            )

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
            label: "Existing",
            width: 520,
            currentSheetURL: URL(string: "https://existing.example/")
        )
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        try withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))
            )
        ) { session, model in
            let input = "Swift concurrency"
            let essential = Essential(name: "Search", key: "s", input: input)
            #expect(session.configuration.preferences.setEssentials([essential]))
            model.showUniversalSearch()
            let target: UniversalSearchItem.Target =
                fromEssential ? .essential(essential.id) : .createBoard(input)

            // Act
            let error = UniversalSearchActions.perform(
                target,
                session: session,
                windowModel: model,
                inDrawer: true,
                openProfile: { _ in false },
                openSettings: {}
            )

            // Assert
            #expect(error == nil)
            let item = try #require(session.resources.state.drawerItems.first)
            #expect(
                item.url
                    == BoardInputResolver.normalizedURL(
                        from: input,
                        searchEngine: session.configuration.preferences.searchEngine
                    )
            )
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [existing.id])
            #expect(model.isDrawerOpen)
            #expect(model.drawer.expandedItemID == item.id)
        }
    }

    @Test(arguments: [
        UniversalSearchItem.Target.createBoard(":tutorial"), .desk(DeskID()), .profile(ProfileID()),
        .board(BoardID()), .command(.toggleZenView),
    ])
    func drawerSubmissionRejectsCommandsAndNavigation(target: UniversalSearchItem.Target) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(desks: [desk]))
            )
        ) { session, model in
            ({
                model.showUniversalSearch()
                var openedProfile = false
                var openedSettings = false

                // Act
                let error = UniversalSearchActions.perform(
                    target,
                    session: session,
                    windowModel: model,
                    inDrawer: true,
                    openProfile: { _ in
                        openedProfile = true
                        return true
                    },
                    openSettings: { openedSettings = true }
                )

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
        withTestSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(makeNativeTestState(boards: [existing])),
                recentItems: [.search("other"), item]
            )
        ) { session in
            do {
                let denWindowComposition = DenWindowComposition(session: session)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let model = denWindowComposition.model

                model.showUniversalSearch()

                // Act
                let error = UniversalSearchActions.perform(
                    .recent(item),
                    session: session,
                    windowModel: model,
                    openProfile: { _ in false },
                    openSettings: {}
                )

                // Assert
                #expect(error == nil)
                #expect(session.navigation.focusedDesk?.boards.count == 2)
                #expect(session.navigation.focusedBoard?.id != existing.id)
                #expect(
                    session.navigation.focusedBoard?.currentSheetURL?.absoluteString
                        == item.displayText
                )
                #expect(session.resources.recentItems.first == item)
                #expect(model.temporaryContext == nil)
            }
        }
    }

    @Test func deskPresetTargetOpensNewDeskPanelWithPreselectedPreset() throws {
        let board = BoardState(label: "Docs", width: 520, currentSheetURL: URL(string: "https://example.com/docs"))
        let desk = DeskState(label: "Source", boards: [board], focusedBoardID: board.id)
        let preset = PersonalDeskPreset(label: "Research", desk: desk)
        let items = UniversalSearch.sourceItems(
            state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id)),
            essentials: [],
            hasBoardUndoHistory: false,
            profiles: [],
            profileName: "personal",
            deskPresets: [preset]
        )
        let results = UniversalSearch.results(query: "docs", items: items, recentItems: [])
        #expect(results.contains { $0.target == .personalDeskPreset(preset.id) })
        #expect(items.contains { $0.target == .builtInDeskPreset(.empty) })
        #expect(items.contains { $0.target == .builtInDeskPreset(.chatGPT) })

        withTestWindow(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(DenState(desks: [desk], focusedDeskID: desk.id)),
                deskPresets: [preset]
            )
        ) { session, model in
            model.showUniversalSearch()
            let error = UniversalSearchActions.perform(
                .personalDeskPreset(preset.id),
                session: session,
                windowModel: model,
                openProfile: { _ in false },
                openSettings: {}
            )
            #expect(error == nil)
            #expect(model.temporaryContext == .newDesk)
            #expect(model.initialNewDeskPreset == .personal(preset.id))
        }
    }
}
