import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct NativeRecentTests {
    @Test func recentURLPageTitleIsOptionalAndBackwardCompatible() throws {
        let url = try #require(URL(string: "https://example.com/"))
        let legacyData = Data(#"{"kind":"url","url":"https://example.com/"}"#.utf8)
        let legacyItem = try JSONDecoder().decode(RecentItem.self, from: legacyData)
        let titledItem = RecentItem.url(url, title: "Example page")
        let decodedTitledItem = try JSONDecoder().decode(
            RecentItem.self,
            from: JSONEncoder().encode(titledItem))

        #expect(legacyItem == .url(url))
        #expect(legacyItem.title == nil)
        #expect(decodedTitledItem.title == "Example page")
        #expect(titledItem == .url(url))
    }

    @Test func webPageTitleUpdatesItsRecentItemOnce() throws {
        let url = try #require(URL(string: "https://example.com/"))
        var savedItems: [RecentItem] = []
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()),
                    onRecentItemsSave: {
                        savedItems = $0
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.openBoard(input: url.absoluteString)
            let boardID = try #require(session.navigation.focusedDesk?.boards.first?.id)
            session.runtimes.updateBoard(boardID: boardID, url: url, title: "Example page")

            #expect(session.resources.recentItems.first?.title == "Example page")
            #expect(savedItems == session.resources.recentItems)

            session.boardOpening.openBoard(input: url.absoluteString)
            #expect(session.resources.recentItems.first?.title == "Example page")

            session.runtimes.updateBoard(
                boardID: boardID,
                url: URL(string: "https://example.com/next"),
                title: "Next page")
            #expect(session.resources.recentItems.first?.title == "Example page")
        }
    }

    @Test func openBoardStoresAndReusesRecentItemsInMostRecentOrder() throws {
        var savedItems: [RecentItem] = []
        let expectedURL = try #require(URL(string: "https://EXAMPLE.com/"))
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()),
                    onRecentItemsSave: {
                        savedItems = $0
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.openBoard(input: "example.com")
            session.boardOpening.openBoard(input: "Swift Observation")
            session.boardOpening.openBoard(input: "https://EXAMPLE.com/")

            #expect(
                session.resources.recentItems == [
                    .url(expectedURL),
                    .search("Swift Observation"),
                ])
            #expect(savedItems == session.resources.recentItems)
        }
    }

    @Test func recentSearchDeduplicationIgnoresCaseAndRepeatedWhitespace() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()), onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.openBoard(input: "Swift   Observation")
            session.boardOpening.openBoard(input: "swift observation")

            #expect(session.resources.recentItems == [.search("swift observation")])
        }
    }

    @Test func pastedLineBreaksDoNotBreakURLOrSearchInput() throws {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()), onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.openBoard(input: "https://example.com/long-\npath")
            session.boardOpening.openBoard(input: "Swift\nObservation")

            #expect(
                session.navigation.focusedDesk?.boards.first?.currentSheetURL
                    == URL(string: "https://example.com/long-path"))
            let searchURL = try #require(
                session.navigation.focusedDesk?.boards.last?.currentSheetURL
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
            #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "Swift Observation")])
            #expect(
                session.resources.recentItems == [
                    .search("Swift Observation"),
                    .url(URL(string: "https://example.com/long-path")!),
                ])

            let composition = DenWindowComposition(session: session)

            let windowModel = composition.model
            composition.connect()
            defer { composition.disconnect() }
            windowModel.openBoard.input = "https://example.com/sub-\npage"
            #expect(windowModel.openBoard.input == "https://example.com/sub-page")

            windowModel.openBoard.input = "search\nquery"
            #expect(windowModel.openBoard.input == "searchquery")

            windowModel.deskFilter.setQuery("desk\nfilter")
            #expect(windowModel.deskFilter.query == "deskfilter")

            windowModel.overview.setQuery("overview\nquery")
            #expect(windowModel.overview.query == "overviewquery")

            windowModel.drawer.setQuery("drawer\nquery")
            #expect(windowModel.drawer.query == "drawerquery")
        }
    }

    @Test func recentKeepsFiveHundredItemsAndClearPersists() {
        var savedItems: [RecentItem] = []
        let initialItems: [RecentItem] = (0...499)
            .reversed()
            .map { .url(URL(string: "https://example.com/\($0)")!) }
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()), recentItems: initialItems,
                    onRecentItemsSave: {
                        savedItems = $0
                        return true
                    }), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.openBoard(input: "https://example.com/500")

            #expect(session.resources.recentItems.count == 500)
            #expect(session.resources.recentItems.first == .url(URL(string: "https://example.com/500")!))
            #expect(session.resources.recentItems.last == .url(URL(string: "https://example.com/1")!))
            #expect(!session.resources.recentItems.contains(.url(URL(string: "https://example.com/0")!)))

            session.resources.recents.clear()

            #expect(session.resources.recentItems.isEmpty)
            #expect(savedItems.isEmpty)
        }
    }

    @Test func failedRecentSaveRestoresItemsWithoutBlockingBoardCreation() {
        let original: [RecentItem] = [.search("existing")]
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()), recentItems: original,
                    onRecentItemsSave: { _ in false }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.openBoard(input: "new search")

            #expect(session.resources.recentItems == original)
            #expect(session.navigation.focusedDesk?.boards.count == 1)
        }
    }

    @Test func terminalAndZellijInputsBecomeRecentItems() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.configuration.preferences.setZellijPath("/opt/homebrew/bin/zellij")
            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path

            session.boardOpening.openBoard(input: ":terminal")
            session.boardOpening.openBoard(input: ":terminal ~")
            session.boardOpening.openBoard(input: ":terminal \(directory)")
            session.boardOpening.openBoard(input: ":zellij")
            session.boardOpening.openBoard(input: ":zellij project-a")
            session.boardOpening.openBoard(input: ":zmx project-a")

            #expect(
                session.resources.recentItems == [
                    .zmx(sessionName: "project-a"),
                    .zellij(sessionName: "project-a"),
                    .zellij(sessionName: nil),
                    .terminal(workingDirectory: directory),
                    .terminal(workingDirectory: home),
                ])
        }
    }

    @Test func essentialLaunchBecomesRecentItem() throws {
        let essential = Essential(name: "Docs", key: "d", input: "https://docs.example/")
        let expectedURL = try #require(URL(string: essential.input))
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            #expect(session.configuration.preferences.setEssentials([essential]))
            session.essentials.launchEssential(id: essential.id)
            #expect(session.resources.recentItems == [.url(expectedURL)])
        }
    }

    @Test func essentialLaunchReportsConfigurationFailure() {
        // Arrange
        let essential = Essential(name: "Project", key: "p", input: ":zmx project")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            #expect(session.configuration.preferences.setEssentials([essential]))
            let initialBoardCount = session.navigation.focusedDesk?.boards.count

            // Act
            session.essentials.launchEssential(id: essential.id)

            // Assert
            #expect(session.navigation.focusedDesk?.boards.count == initialBoardCount)
            #expect(
                session.feedback.latest?.message
                    == "Set an absolute zmx executable path in Settings > Terminal.")
            #expect(session.feedback.latest?.severity == .warning)
        }
    }

    @Test func openingZmxSessionsPickerDoesNotCreateRecentItem() {
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(state: DenStateNormalization.normalize(makeNativeTestState())),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            session.boardOpening.openBoard(input: ":zmx")

            #expect(session.resources.recentItems.isEmpty)
        }
    }

    @Test func openingTerminalRecentRevalidatesDirectoryAndMovesItToTheFront() {
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let item = RecentItem.terminal(workingDirectory: directory)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()),
                    recentItems: [.search("existing"), item], onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.boardOpening.openBoard(recentItem: item)

            #expect(session.navigation.focusedBoard?.terminalWorkingDirectory == directory)
            #expect(session.resources.recentItems.first == item)
        }
    }

    @Test func missingTerminalRecentShowsErrorWithoutCreatingBoard() {
        let item = RecentItem.terminal(
            workingDirectory: "/missing/den-browser-\(UUID().uuidString)")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()), recentItems: [item],
                    onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            do {
                let denWindowSession = session
                let denWindowComposition = DenWindowComposition(session: denWindowSession)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                session.boardOpening.openBoard(recentItem: item)

                #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
                #expect(windowModel.openBoard.message?.contains("does not exist") == true)
                #expect(session.resources.recentItems == [item])
            }
        }
    }

    @Test func openingZellijRecentCreatesBoardAndMovesItToTheFront() {
        let item = RecentItem.zellij(sessionName: "project-a")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()),
                    recentItems: [.search("existing"), item], onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.configuration.preferences.setZellijPath("/opt/homebrew/bin/zellij")
            session.boardOpening.openBoard(recentItem: item)

            #expect(session.navigation.focusedBoard?.isZellij == true)
            #expect(session.navigation.focusedBoard?.zellijSessionName == "project-a")
            #expect(session.resources.recentItems.first == item)
        }
    }

    @Test func openingZmxRecentCreatesBoardAndMovesItToTheFront() {
        let item = RecentItem.zmx(sessionName: "project-a")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()),
                    recentItems: [.search("existing"), item], onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            session.boardOpening.openBoard(recentItem: item)

            #expect(session.navigation.focusedBoard?.isZmx == true)
            #expect(session.navigation.focusedBoard?.zmxSessionName == "project-a")
            #expect(session.resources.recentItems.first == item)
        }
    }

    @Test func openingZellijRecentWithoutConfigurationShowsError() {
        let item = RecentItem.zellij(sessionName: nil)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()), recentItems: [item],
                    onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            do {
                let denWindowSession = session
                let denWindowComposition = DenWindowComposition(session: denWindowSession)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                session.boardOpening.openBoard(recentItem: item)

                #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
                #expect(
                    windowModel.openBoard.message?.contains("absolute Zellij executable path") == true)
                #expect(session.resources.recentItems == [item])
            }
        }
    }

    @Test func openingZmxRecentWithoutConfigurationShowsError() {
        let item = RecentItem.zmx(sessionName: "project-a")
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState()), recentItems: [item],
                    onRecentItemsSave: { _ in true }),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            do {
                let denWindowSession = session
                let denWindowComposition = DenWindowComposition(session: denWindowSession)
                denWindowComposition.connect()
                defer { denWindowComposition.disconnect() }
                let windowModel = denWindowComposition.model

                session.boardOpening.openBoard(recentItem: item)

                #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
                #expect(windowModel.openBoard.message?.contains("absolute zmx executable path") == true)
                #expect(session.resources.recentItems == [item])
            }
        }
    }

    @Test func recentItemMatchesEssentialByInput() {
        let urlItem = RecentItem.url(URL(string: "https://example.com/")!)
        let searchItem = RecentItem.search("rust docs")
        let terminalItem = RecentItem.terminal(workingDirectory: "/tmp/project")
        let zellijItem = RecentItem.zellij(sessionName: "dev")
        let zmxItem = RecentItem.zmx(sessionName: "work")

        let urlEssential = Essential(name: "Example", key: "e", input: "https://example.com")
        let searchEssential = Essential(name: "Rust", key: "r", input: "rust docs")
        let terminalEssential = Essential(name: "Terminal", key: "t", input: ":terminal /tmp/project")
        let zellijEssential = Essential(name: "Zellij", key: "z", input: ":zellij dev")
        let zmxEssential = Essential(name: "zmx", key: "x", input: ":zmx work")
        let unrelatedEssential = Essential(name: "Other", key: "o", input: "https://other.com")

        #expect(urlItem.matches(essential: urlEssential))
        #expect(searchItem.matches(essential: searchEssential))
        #expect(terminalItem.matches(essential: terminalEssential))
        #expect(zellijItem.matches(essential: zellijEssential))
        #expect(zmxItem.matches(essential: zmxEssential))
        #expect(!urlItem.matches(essential: unrelatedEssential))
    }
}
