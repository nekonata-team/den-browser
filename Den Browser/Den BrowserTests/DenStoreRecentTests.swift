import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenStoreRecentTests {
    @Test func openBoardStoresAndReusesRecentItemsInMostRecentOrder() throws {
        var savedItems: [RecentItem] = []
        let expectedURL = try #require(URL(string: "https://EXAMPLE.com/"))
        withTestStore(
            onRecentItemsSave: {
                savedItems = $0
                return true
            },
            body: { store in
                store.openBoard(input: "example.com")
                store.openBoard(input: "Swift Observation")
                store.openBoard(input: "https://EXAMPLE.com/")

                #expect(
                    store.recentItems == [
                        .url(expectedURL),
                        .search("Swift Observation"),
                    ])
                #expect(savedItems == store.recentItems)
            })
    }

    @Test func recentSearchDeduplicationIgnoresCaseAndRepeatedWhitespace() {
        withTestStore(
            onRecentItemsSave: { _ in true },
            body: { store in
                store.openBoard(input: "Swift   Observation")
                store.openBoard(input: "swift observation")

                #expect(store.recentItems == [.search("swift observation")])
            })
    }

    @Test func pastedLineBreaksDoNotBreakURLOrSearchInput() throws {
        try withTestStore(
            onRecentItemsSave: { _ in true },
            body: { store in
                store.openBoard(input: "https://example.com/long-\npath")
                store.openBoard(input: "Swift\nObservation")

                #expect(
                    store.focusedDesk?.boards.first?.currentSheetURL == URL(string: "https://example.com/long-path"))
                let searchURL = try #require(
                    store.focusedDesk?.boards.last?.currentSheetURL
                        .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
                #expect(searchURL.queryItems == [URLQueryItem(name: "q", value: "Swift Observation")])
                #expect(
                    store.recentItems == [
                        .search("Swift Observation"),
                        .url(URL(string: "https://example.com/long-path")!),
                    ])
            })
    }

    @Test func recentKeepsOneHundredItemsAndClearPersists() {
        var savedItems: [RecentItem] = []
        withTestStore(
            onRecentItemsSave: {
                savedItems = $0
                return true
            },
            body: { store in
                for index in 0...100 {
                    store.openBoard(input: "https://example.com/\(index)")
                }

                #expect(store.recentItems.count == 100)
                #expect(store.recentItems.first == .url(URL(string: "https://example.com/100")!))
                #expect(store.recentItems.last == .url(URL(string: "https://example.com/1")!))

                store.clearRecent()

                #expect(store.recentItems.isEmpty)
                #expect(savedItems.isEmpty)
            })
    }

    @Test func failedRecentSaveRestoresItemsWithoutBlockingBoardCreation() {
        let original: [RecentItem] = [.search("existing")]
        withTestStore(
            recentItems: original,
            onRecentItemsSave: { _ in false },
            body: { store in
                store.openBoard(input: "new search")

                #expect(store.recentItems == original)
                #expect(store.focusedDesk?.boards.count == 1)
            })
    }

    @Test func terminalAndZellijInputsBecomeRecentItems() {
        withTestStore { store in
            store.preferences.setZellijPath("/opt/homebrew/bin/zellij")
            store.preferences.setZmxPath("/opt/homebrew/bin/zmx")
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
            let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path

            store.openBoard(input: ":terminal")
            store.openBoard(input: ":terminal ~")
            store.openBoard(input: ":terminal \(directory)")
            store.openBoard(input: ":zellij")
            store.openBoard(input: ":zellij project-a")
            store.openBoard(input: ":zmx project-a")

            #expect(
                store.recentItems == [
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
        withTestStore { store in
            #expect(store.preferences.setEssentials([essential]))

            store.launchEssential(id: essential.id)

            #expect(store.recentItems == [.url(expectedURL)])
        }
    }

    @Test func openingZmxSessionsPickerDoesNotCreateRecentItem() {
        withTestStore { store in
            store.preferences.setZmxPath("/opt/homebrew/bin/zmx")

            store.openBoard(input: ":zmx")

            #expect(store.recentItems.isEmpty)
        }
    }

    @Test func openingTerminalRecentRevalidatesDirectoryAndMovesItToTheFront() {
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let item = RecentItem.terminal(workingDirectory: directory)
        withTestStore(
            recentItems: [.search("existing"), item],
            onRecentItemsSave: { _ in true },
            body: { store in
                store.openBoard(recentItem: item)

                #expect(store.focusedBoard?.terminalWorkingDirectory == directory)
                #expect(store.recentItems.first == item)
            })
    }

    @Test func missingTerminalRecentShowsErrorWithoutCreatingBoard() {
        let item = RecentItem.terminal(
            workingDirectory: "/missing/den-browser-\(UUID().uuidString)")
        withTestStore(
            recentItems: [item],
            onRecentItemsSave: { _ in true },
            body: { store in
                store.openBoard(recentItem: item)

                #expect(store.focusedDesk?.boards.isEmpty == true)
                #expect(store.openBoardPanelMessage?.contains("does not exist") == true)
                #expect(store.recentItems == [item])
            })
    }

    @Test func openingZellijRecentCreatesBoardAndMovesItToTheFront() {
        let item = RecentItem.zellij(sessionName: "project-a")
        withTestStore(
            recentItems: [.search("existing"), item],
            onRecentItemsSave: { _ in true },
            body: { store in
                store.preferences.setZellijPath("/opt/homebrew/bin/zellij")
                store.openBoard(recentItem: item)

                #expect(store.focusedBoard?.isZellij == true)
                #expect(store.focusedBoard?.zellijSessionName == "project-a")
                #expect(store.recentItems.first == item)
            })
    }

    @Test func openingZmxRecentCreatesBoardAndMovesItToTheFront() {
        let item = RecentItem.zmx(sessionName: "project-a")
        withTestStore(
            recentItems: [.search("existing"), item],
            onRecentItemsSave: { _ in true },
            body: { store in
                store.preferences.setZmxPath("/opt/homebrew/bin/zmx")
                store.openBoard(recentItem: item)

                #expect(store.focusedBoard?.isZmx == true)
                #expect(store.focusedBoard?.zmxSessionName == "project-a")
                #expect(store.recentItems.first == item)
            })
    }

    @Test func openingZellijRecentWithoutConfigurationShowsError() {
        let item = RecentItem.zellij(sessionName: nil)
        withTestStore(
            recentItems: [item],
            onRecentItemsSave: { _ in true },
            body: { store in
                store.openBoard(recentItem: item)

                #expect(store.focusedDesk?.boards.isEmpty == true)
                #expect(store.openBoardPanelMessage?.contains("absolute Zellij executable path") == true)
                #expect(store.recentItems == [item])
            })
    }

    @Test func openingZmxRecentWithoutConfigurationShowsError() {
        let item = RecentItem.zmx(sessionName: "project-a")
        withTestStore(
            recentItems: [item],
            onRecentItemsSave: { _ in true },
            body: { store in
                store.openBoard(recentItem: item)

                #expect(store.focusedDesk?.boards.isEmpty == true)
                #expect(store.openBoardPanelMessage?.contains("absolute zmx executable path") == true)
                #expect(store.recentItems == [item])
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
