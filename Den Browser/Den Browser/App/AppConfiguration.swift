import Foundation
import WebKit

struct AppConfiguration {
    let profileDirectoryURL: URL
    let defaults: UserDefaults
    let initialProfile: PersistedProfile?
    let websiteDataStore: (WebProfileStore) -> WKWebsiteDataStore

    static func current(processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        guard processInfo.arguments.contains("--ui-testing") else {
            return AppConfiguration(
                profileDirectoryURL: ProfileManager.defaultDirectoryURL(),
                defaults: .standard,
                initialProfile: nil,
                websiteDataStore: { $0.websiteDataStore })
        }

        guard
            let fixtureName = argumentValue(after: "--fixture", in: processInfo.arguments),
            let fixture = UITestFixture(rawValue: fixtureName)
        else {
            preconditionFailure("UI tests require a supported fixture")
        }
        let boardCountArgument =
            argumentValue(after: "--board-count", in: processInfo.arguments)
            ?? UITestBoardCount.three.rawValue
        guard let boardCount = UITestBoardCount(rawValue: boardCountArgument) else {
            preconditionFailure("UI tests require a supported Board count")
        }

        let runID = processInfo.environment["DEN_UI_TEST_RUN_ID"] ?? UUID().uuidString
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserUITests", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let suiteName = "dev.nekonata.denbrowser.ui-testing"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create UI test preferences")
        }
        defaults.removePersistentDomain(forName: suiteName)
        if processInfo.arguments.contains("--enable-sheet-navigation") {
            defaults.set(true, forKey: SheetNavigationManager.enabledKey)
        }
        if processInfo.arguments.contains("--center-boards-on-overflow") {
            AppPreferences(defaults: defaults).setBoardCentering(.onOverflow)
        }
        if processInfo.arguments.contains("--center-boards-always") {
            AppPreferences(defaults: defaults).setBoardCentering(.always)
        }

        return AppConfiguration(
            profileDirectoryURL: directoryURL,
            defaults: defaults,
            initialProfile: uiTestProfile(
                fixture: fixture,
                boardCount: boardCount,
                terminalBoard: processInfo.arguments.contains("--terminal-board"),
                multipleDrawerItems: processInfo.arguments.contains("--multiple-drawer-items")),
            websiteDataStore: { _ in .nonPersistent() })
    }

    private static func argumentValue(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func uiTestProfile(
        fixture: UITestFixture,
        boardCount: UITestBoardCount,
        terminalBoard: Bool,
        multipleDrawerItems: Bool = false
    ) -> PersistedProfile {
        let alpha =
            if terminalBoard {
                BoardState(
                    id: fixtureID("00000000-0000-0000-0000-000000000301"),
                    label: "Terminal",
                    width: 320,
                    workingDirectory: "/tmp")
            } else {
                BoardState(
                    id: fixtureID("00000000-0000-0000-0000-000000000301"),
                    label: "Alpha",
                    width: 320,
                    currentSheetURL: URL(string: fixtureSheetURL))
            }
        let bravo = BoardState(
            id: fixtureID("00000000-0000-0000-0000-000000000302"),
            label: "Bravo",
            width: 320,
            currentSheetURL: URL(string: fixtureSheetURL))
        let charlie = BoardState(
            id: fixtureID("00000000-0000-0000-0000-000000000303"),
            label: "Charlie",
            width: 320,
            currentSheetURL: URL(string: fixtureSheetURL))
        let mainDeskID = fixtureID("00000000-0000-0000-0000-000000000200")
        let secondDeskID = fixtureID("00000000-0000-0000-0000-000000000201")
        let thirdDeskID = fixtureID("00000000-0000-0000-0000-000000000202")
        let mainBoards: [BoardState]
        let secondBoards: [BoardState]
        let secondFocusedBoardID: UUID?
        let mainFocusedBoardID: UUID
        let focusedDeskID: UUID
        switch fixture {
        case .interactionBasics:
            mainBoards =
                switch boardCount {
                case .one: [alpha]
                case .two: [alpha, bravo]
                case .three: [alpha, bravo, charlie]
                }
            secondBoards = []
            secondFocusedBoardID = nil
            mainFocusedBoardID = alpha.id
            focusedDeskID = mainDeskID
        case .overviewBoardPair:
            mainBoards = [bravo, charlie]
            secondBoards = []
            secondFocusedBoardID = nil
            mainFocusedBoardID = bravo.id
            focusedDeskID = mainDeskID
        case .focusedNonLeadingBoard:
            mainBoards = [alpha]
            secondBoards = [bravo, charlie]
            secondFocusedBoardID = charlie.id
            mainFocusedBoardID = alpha.id
            focusedDeskID = secondDeskID
        }
        let desk = DeskState(
            id: mainDeskID,
            label: "Main",
            boards: mainBoards,
            focusedBoardID: mainFocusedBoardID)
        let secondDesk = DeskState(
            id: secondDeskID,
            label: "Second",
            boards: secondBoards,
            focusedBoardID: secondFocusedBoardID)
        let thirdDesk = DeskState(
            id: thirdDeskID,
            label: "Third",
            boards: [])
        let drawerItem = DrawerItem(
            id: fixtureID("00000000-0000-0000-0000-000000000401"),
            url: fixtureSheetURLValue(),
            title: "Drawer Fixture")
        let secondDrawerItem = DrawerItem(
            id: fixtureID("00000000-0000-0000-0000-000000000402"),
            url: fixtureSheetURLValue(),
            title: "Next Drawer Fixture")
        let drawerItems = multipleDrawerItems ? [secondDrawerItem, drawerItem] : [drawerItem]
        return PersistedProfile(
            profile: ProfileState(
                id: fixtureID("00000000-0000-0000-0000-000000000100"),
                name: "UI Testing",
                color: .blue,
                webProfileStore: .default),
            den: DenState(
                desks: [desk, secondDesk, thirdDesk],
                focusedDeskID: focusedDeskID,
                drawerItems: drawerItems,
                expandedDrawerItemID: multipleDrawerItems ? secondDrawerItem.id : drawerItem.id))
    }

    private static let fixtureSheetURL: String = {
        guard
            let url = Bundle.main.url(forResource: "interaction-basics", withExtension: "html"),
            let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("Could not load UI test fixture")
        }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#"))
        guard let encoded = html.addingPercentEncoding(withAllowedCharacters: allowed) else {
            preconditionFailure("Could not encode UI test fixture")
        }
        return "data:text/html,\(encoded)"
    }()

    private static func fixtureID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid UI test fixture UUID: \(value)")
        }
        return id
    }

    private static func fixtureSheetURLValue() -> URL {
        guard let url = URL(string: fixtureSheetURL) else {
            preconditionFailure("Invalid UI test fixture URL")
        }
        return url
    }
}

private enum UITestFixture: String {
    case interactionBasics = "interaction-basics"
    case overviewBoardPair = "overview-board-pair"
    case focusedNonLeadingBoard = "focused-non-leading-board"
}

private enum UITestBoardCount: String {
    case one
    case two
    case three
}
