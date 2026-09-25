import Foundation

enum UITestFixtureFactory {
    private static let resourceBundle = Bundle(for: Den_BrowserUITests.self)

    static func makeProfileSeed(
        fixture: UITestFixture,
        boardCount: UITestBoardCount = .three,
        terminalBoard: Bool = false,
        multipleDrawerItems: Bool = false
    ) throws -> Data {
        let alphaID = FixtureBoard.alpha.rawValue
        let bravoID = FixtureBoard.bravo.rawValue
        let charlieID = FixtureBoard.charlie.rawValue
        let mainDeskID = FixtureDesk.main.rawValue
        let secondDeskID = FixtureDesk.second.rawValue
        let thirdDeskID = FixtureDesk.third.rawValue
        let sheetURL = fixtureSheetURL().absoluteString
        func webBoard(_ id: String, _ label: String, width: Double = 320) -> [String: Any] {
            [
                "id": id, "label": label, "width": width,
                "content": ["kind": "web", "currentSheetURL": sheetURL, "firstSheetURL": sheetURL],
                "sheetNavigationPaused": false,
            ]
        }
        func makeTerminalBoard(_ id: String, _ label: String, width: Double = 320) -> [String: Any] {
            [
                "id": id, "label": label, "width": width,
                "content": ["kind": "terminal", "workingDirectory": "/tmp"],
                "sheetNavigationPaused": false,
            ]
        }
        let alpha = terminalBoard ? makeTerminalBoard(alphaID, "Terminal") : webBoard(alphaID, "Alpha")
        let bravo = webBoard(bravoID, "Bravo")
        let charlie = webBoard(charlieID, "Charlie")
        let mainBoards: [[String: Any]]
        let secondBoards: [[String: Any]]
        let secondFocusedBoardID: String?
        let mainFocusedBoardID: String
        let focusedDeskID: String
        switch fixture {
        case .interactionBasics:
            switch boardCount {
            case .one: mainBoards = [alpha]
            case .two: mainBoards = [alpha, bravo]
            case .three: mainBoards = [alpha, bravo, charlie]
            }
            secondBoards = []
            secondFocusedBoardID = nil
            mainFocusedBoardID = alphaID
            focusedDeskID = mainDeskID
        case .overviewBoardPair:
            mainBoards = [bravo, charlie]
            secondBoards = []
            secondFocusedBoardID = nil
            mainFocusedBoardID = bravoID
            focusedDeskID = mainDeskID
        case .focusedNonLeadingBoard:
            mainBoards = [alpha]
            secondBoards = [bravo, charlie]
            secondFocusedBoardID = charlieID
            mainFocusedBoardID = alphaID
            focusedDeskID = secondDeskID
        case .focusedTerminalBeforeAlignment:
            let leadingBoard =
                terminalBoard
                ? makeTerminalBoard(alphaID, "Terminal", width: 1_400)
                : webBoard(alphaID, "Alpha", width: 1_400)
            let middleBoard = webBoard(bravoID, "Bravo", width: 1_400)
            let focusedBoard = webBoard(charlieID, "Charlie", width: 1_400)
            let mainBoard = webBoard("00000000-0000-0000-0000-000000000304", "Main")
            mainBoards = [mainBoard]
            secondBoards = [leadingBoard, middleBoard, focusedBoard]
            secondFocusedBoardID = charlieID
            mainFocusedBoardID = "00000000-0000-0000-0000-000000000304"
            focusedDeskID = secondDeskID
        }
        let desk: [String: Any] = [
            "id": mainDeskID, "label": "Main", "boards": mainBoards,
            "focusedBoardID": mainFocusedBoardID,
        ]
        let secondDesk: [String: Any] = [
            "id": secondDeskID, "label": "Second", "boards": secondBoards,
            "focusedBoardID": secondFocusedBoardID as Any? ?? NSNull(),
        ]
        let thirdDesk: [String: Any] = ["id": thirdDeskID, "label": "Third", "boards": [] as [[String: Any]]]
        let drawerItem: [String: Any] = [
            "id": "00000000-0000-0000-0000-000000000401", "url": sheetURL, "title": "Drawer Fixture",
        ]
        let secondDrawerItem: [String: Any] = [
            "id": "00000000-0000-0000-0000-000000000402", "url": sheetURL, "title": "Next Drawer Fixture",
        ]
        let drawerItems = multipleDrawerItems ? [secondDrawerItem, drawerItem] : [drawerItem]
        let seed: [String: Any] = [
            "schemaVersion": 2,
            "profile": [
                "id": "00000000-0000-0000-0000-000000000100", "name": "UI Testing",
                "color": "blue", "webProfileStore": ["kind": "default"],
            ],
            "den": [
                "desks": [desk, secondDesk, thirdDesk], "focusedDeskID": focusedDeskID,
                "drawerItems": drawerItems,
            ],
            "deskPresets": [],
        ]
        return try JSONSerialization.data(withJSONObject: seed)
    }

    private static func fixtureSheetURL() -> URL {
        guard
            let url = resourceBundle.url(forResource: "interaction-basics", withExtension: "html"),
            let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("Could not load UI test fixture")
        }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#"))
        guard
            let encoded = html.addingPercentEncoding(withAllowedCharacters: allowed),
            let url = URL(string: "data:text/html,\(encoded)")
        else {
            preconditionFailure("Could not encode UI test fixture")
        }
        return url
    }
}

enum UITestFixture: String {
    case interactionBasics = "interaction-basics"
    case overviewBoardPair = "overview-board-pair"
    case focusedNonLeadingBoard = "focused-non-leading-board"
    case focusedTerminalBeforeAlignment = "focused-terminal-before-alignment"

    var initialBoard: FixtureBoard {
        switch self {
        case .focusedNonLeadingBoard, .focusedTerminalBeforeAlignment: .charlie
        case .overviewBoardPair: .bravo
        default: .alpha
        }
    }
}

enum FixtureBoard: String, CaseIterable {
    case alpha = "00000000-0000-0000-0000-000000000301"
    case bravo = "00000000-0000-0000-0000-000000000302"
    case charlie = "00000000-0000-0000-0000-000000000303"

    static var allSurfaceIdentifiers: Set<String> {
        Set(allCases.map { "board-surface.\($0.rawValue)" })
    }
}

enum FixtureDesk: String {
    case main = "00000000-0000-0000-0000-000000000200"
    case second = "00000000-0000-0000-0000-000000000201"
    case third = "00000000-0000-0000-0000-000000000202"
}

enum UITestBoardCount: String {
    case one
    case two
    case three
}
