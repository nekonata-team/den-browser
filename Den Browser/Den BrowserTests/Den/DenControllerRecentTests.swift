import DenDomain
import DenPresentation
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerRecentTests {
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
        try withTestController(
            onRecentItemsSave: {
                savedItems = $0
                return true
            },
            body: { controller in
                controller.openBoard(input: url.absoluteString)
                let boardID = try #require(controller.focusedDesk?.boards.first?.id)
                controller.updateBoard(boardID: boardID, url: url, title: "Example page")

                #expect(controller.recentItems.first?.title == "Example page")
                #expect(savedItems == controller.recentItems)

                controller.openBoard(input: url.absoluteString)
                #expect(controller.recentItems.first?.title == "Example page")

                controller.updateBoard(
                    boardID: boardID,
                    url: URL(string: "https://example.com/next"),
                    title: "Next page")
                #expect(controller.recentItems.first?.title == "Example page")
            })
    }

    @Test func openBoardStoresAndReusesRecentItemsInMostRecentOrder() throws {
        var savedItems: [RecentItem] = []
        let expectedURL = try #require(URL(string: "https://EXAMPLE.com/"))
        withTestController(
            onRecentItemsSave: {
                savedItems = $0
                return true
            },
            body: { controller in
                controller.openBoard(input: "example.com")
                controller.openBoard(input: "Swift Observation")
                controller.openBoard(input: "https://EXAMPLE.com/")

                #expect(
                    controller.recentItems == [
                        .url(expectedURL),
                        .search("Swift Observation"),
                    ])
                #expect(savedItems == controller.recentItems)
            })
    }

    @Test func recentSearchDeduplicationIgnoresCaseAndRepeatedWhitespace() {
        withTestController(
            onRecentItemsSave: { _ in true },
            body: { controller in
                controller.openBoard(input: "Swift   Observation")
                controller.openBoard(input: "swift observation")

                #expect(controller.recentItems == [.search("swift observation")])
            })
    }

    @Test func pastedLineBreaksDoNotBreakURLOrSearchInput() throws {
        try withTestController(
            onRecentItemsSave: { _ in true },
            body: { controller in
                controller.openBoard(input: "https://example.com/long-\npath")
                controller.openBoard(input: "Swift\nObservation")

                #expect(
                    controller.focusedDesk?.boards.first?.currentSheetURL
                        == URL(string: "https://example.com/long-path"))
                let searchURL = try #require(
                    controller.focusedDesk?.boards.last?.currentSheetURL
                        .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
                #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "Swift Observation")])
                #expect(
                    controller.recentItems == [
                        .search("Swift Observation"),
                        .url(URL(string: "https://example.com/long-path")!),
                    ])

                let composition = DenWindowComposition(controller: controller)

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
            })
    }

    @Test func recentKeepsFiveHundredItemsAndClearPersists() {
        var savedItems: [RecentItem] = []
        let initialItems: [RecentItem] = (0...499)
            .reversed()
            .map { .url(URL(string: "https://example.com/\($0)")!) }
        withTestController(
            recentItems: initialItems,
            onRecentItemsSave: {
                savedItems = $0
                return true
            },
            body: { controller in
                controller.openBoard(input: "https://example.com/500")

                #expect(controller.recentItems.count == 500)
                #expect(controller.recentItems.first == .url(URL(string: "https://example.com/500")!))
                #expect(controller.recentItems.last == .url(URL(string: "https://example.com/1")!))
                #expect(!controller.recentItems.contains(.url(URL(string: "https://example.com/0")!)))

                controller.clearRecent()

                #expect(controller.recentItems.isEmpty)
                #expect(savedItems.isEmpty)
            })
    }

    @Test func failedRecentSaveRestoresItemsWithoutBlockingBoardCreation() {
        let original: [RecentItem] = [.search("existing")]
        withTestController(
            recentItems: original,
            onRecentItemsSave: { _ in false },
            body: { controller in
                controller.openBoard(input: "new search")

                #expect(controller.recentItems == original)
                #expect(controller.focusedDesk?.boards.count == 1)
            })
    }

    @Test func terminalAndZellijInputsBecomeRecentItems() {
        withTestController { controller in
            controller.preferences.setZellijPath("/opt/homebrew/bin/zellij")
            controller.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path

            controller.openBoard(input: ":terminal")
            controller.openBoard(input: ":terminal ~")
            controller.openBoard(input: ":terminal \(directory)")
            controller.openBoard(input: ":zellij")
            controller.openBoard(input: ":zellij project-a")
            controller.openBoard(input: ":zmx project-a")

            #expect(
                controller.recentItems == [
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
        withTestController { controller in
            #expect(controller.preferences.setEssentials([essential]))
            controller.launchEssential(id: essential.id)
            #expect(controller.recentItems == [.url(expectedURL)])
        }
    }

    @Test func essentialLaunchReportsConfigurationFailure() {
        // Arrange
        let essential = Essential(name: "Project", key: "p", input: ":zmx project")
        withTestController { controller in
            #expect(controller.preferences.setEssentials([essential]))
            let initialBoardCount = controller.focusedDesk?.boards.count

            // Act
            controller.launchEssential(id: essential.id)

            // Assert
            #expect(controller.focusedDesk?.boards.count == initialBoardCount)
            #expect(controller.latestFeedback?.message == "Set an absolute zmx executable path in Settings > Terminal.")
            #expect(controller.latestFeedback?.severity == .warning)
        }
    }

    @Test func openingZmxSessionsPickerDoesNotCreateRecentItem() {
        withTestController { controller in
            controller.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            controller.openBoard(input: ":zmx")

            #expect(controller.recentItems.isEmpty)
        }
    }

    @Test func openingTerminalRecentRevalidatesDirectoryAndMovesItToTheFront() {
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let item = RecentItem.terminal(workingDirectory: directory)
        withTestController(
            recentItems: [.search("existing"), item],
            onRecentItemsSave: { _ in true },
            body: { controller in
                controller.openBoard(recentItem: item)

                #expect(controller.focusedBoard?.terminalWorkingDirectory == directory)
                #expect(controller.recentItems.first == item)
            })
    }

    @Test func missingTerminalRecentShowsErrorWithoutCreatingBoard() {
        let item = RecentItem.terminal(
            workingDirectory: "/missing/den-browser-\(UUID().uuidString)")
        withTestController(
            recentItems: [item],
            onRecentItemsSave: { _ in true },
            body: { controller in
                withTestWindowModel(controller: controller) { windowModel in
                    controller.openBoard(recentItem: item)

                    #expect(controller.focusedDesk?.boards.isEmpty == true)
                    #expect(windowModel.openBoard.message?.contains("does not exist") == true)
                    #expect(controller.recentItems == [item])
                }
            })
    }

    @Test func openingZellijRecentCreatesBoardAndMovesItToTheFront() {
        let item = RecentItem.zellij(sessionName: "project-a")
        withTestController(
            recentItems: [.search("existing"), item],
            onRecentItemsSave: { _ in true },
            body: { controller in
                controller.preferences.setZellijPath("/opt/homebrew/bin/zellij")
                controller.openBoard(recentItem: item)

                #expect(controller.focusedBoard?.isZellij == true)
                #expect(controller.focusedBoard?.zellijSessionName == "project-a")
                #expect(controller.recentItems.first == item)
            })
    }

    @Test func openingZmxRecentCreatesBoardAndMovesItToTheFront() {
        let item = RecentItem.zmx(sessionName: "project-a")
        withTestController(
            recentItems: [.search("existing"), item],
            onRecentItemsSave: { _ in true },
            body: { controller in
                controller.preferences.setZmxPath("/opt/homebrew/bin/zmx")
                controller.openBoard(recentItem: item)

                #expect(controller.focusedBoard?.isZmx == true)
                #expect(controller.focusedBoard?.zmxSessionName == "project-a")
                #expect(controller.recentItems.first == item)
            })
    }

    @Test func openingZellijRecentWithoutConfigurationShowsError() {
        let item = RecentItem.zellij(sessionName: nil)
        withTestController(
            recentItems: [item],
            onRecentItemsSave: { _ in true },
            body: { controller in
                withTestWindowModel(controller: controller) { windowModel in
                    controller.openBoard(recentItem: item)

                    #expect(controller.focusedDesk?.boards.isEmpty == true)
                    #expect(windowModel.openBoard.message?.contains("absolute Zellij executable path") == true)
                    #expect(controller.recentItems == [item])
                }
            })
    }

    @Test func openingZmxRecentWithoutConfigurationShowsError() {
        let item = RecentItem.zmx(sessionName: "project-a")
        withTestController(
            recentItems: [item],
            onRecentItemsSave: { _ in true },
            body: { controller in
                withTestWindowModel(controller: controller) { windowModel in
                    controller.openBoard(recentItem: item)

                    #expect(controller.focusedDesk?.boards.isEmpty == true)
                    #expect(windowModel.openBoard.message?.contains("absolute zmx executable path") == true)
                    #expect(controller.recentItems == [item])
                }
            })
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
