import AppKit
import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DenControllerPersistenceTests {

    @Test func sheetScaleAndContentSizeAdjustmentsApplyToWebRuntime() throws {
        // Arrange
        let suiteName = "SheetScaleAndContentSizeTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setSheetScale(80)
        let sheetNavigation = SheetNavigationManager(defaults: defaults)
        let board = board("Board")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        let controller = DenController(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: sheetNavigation,
            preferences: preferences)

        // 1. Initial global scale applied to new board runtime (80%)
        let runtime = controller.webRuntime(for: board)
        #expect(runtime.webView.pageZoom == 0.8)

        // 2. Adjust individual sheet size (+1 step from 80% -> 90%)
        runtime.webView.magnification = 1.2
        controller.adjustFocusedSheetSize(by: 1)
        #expect(runtime.webView.pageZoom == 0.9)
        #expect(runtime.webView.magnification == 1)
        #expect(controller.state.desks[0].boards[0] == board)

        // 3. Reset individual sheet size back to global scale (80%)
        runtime.webView.magnification = 1.2
        controller.resetFocusedSheetSize()
        #expect(runtime.webView.pageZoom == 0.8)
        #expect(runtime.webView.magnification == 1)

        // 4. Change global sheet scale and apply to live runtime (100%)
        preferences.setSheetScale(100)
        runtime.webView.magnification = 1.2
        controller.applySheetScale(preferences.sheetScale)
        #expect(runtime.webView.pageZoom == 1.0)
        #expect(runtime.webView.magnification == 1)

        // 5. Adjust individual sheet size from 100% (+1 step -> 1.1)
        controller.adjustFocusedSheetSize(by: 1)
        #expect(runtime.webView.pageZoom == 1.1)
        #expect(runtime.webView.magnification == 1)
    }

    @Test func emptyPersistedDenRecoversAndSavesOneDesk() {
        // Arrange
        var savedState: DenState?

        // Act
        let controller = DenController(
            state: DenState(desks: [], focusedDeskID: DeskID()),
            onSave: { savedState = $0 })

        // Assert
        #expect(controller.state.desks.count == 1)
        #expect(controller.focusedDesk != nil)
        #expect(savedState == controller.state)
    }

    @Test func tutorialBoardAndProgressStayInMemory() throws {
        // Arrange
        var savedState: DenState?
        var saveCount = 0
        let controller = DenController(
            state: .sample,
            onSave: { state in
                savedState = state
                saveCount += 1
            })

        // Act
        #expect(controller.openTutorialBoard())
        let saveCountAfterOpening = saveCount
        controller.dispatchDenOperationEvent(.webBoardOpened)

        // Assert
        #expect(controller.state.desks[0].boards.first?.isTutorial == true)
        #expect(
            controller.state.desks[0].boards.first?.tutorialCompletedSteps?.contains(.openBoard) == true)
        #expect(saveCount == saveCountAfterOpening)
        #expect(controller.save())
        #expect(savedState?.desks[0].boards.isEmpty == true)

        let encodedContent = try JSONEncoder().encode(
            BoardKind.tutorial(TutorialBoardState(completedSteps: [.openBoard])))
        let content = try JSONSerialization.jsonObject(with: encodedContent) as? [String: String]
        #expect(content == ["kind": "tutorial"])

        let oldContent = Data(
            #"""
            {
              "kind": "tutorial",
              "selectedTutorialID": "getting-started",
              "completedStepIDs": ["getting-started.open-board"]
            }
            """#.utf8)
        #expect(
            try JSONDecoder().decode(BoardKind.self, from: oldContent)
                == .tutorial(TutorialBoardState()))
    }

    @Test func persistedStateRestoresDeskAndBoardDataAndFocus() throws {
        // Arrange
        let firstBoards = [
            board("One", width: 440, url: "https://one.example/path"),
            board("Two", width: 760, url: "https://two.example/"),
        ]
        let secondBoards = [board("Three", width: 980, url: "https://three.example/query?q=1")]
        let first = desk("First", boards: firstBoards, focusedBoardID: firstBoards[1].id)
        let second = desk("Second", boards: secondBoards, focusedBoardID: secondBoards[0].id)
        var persistedState: DenState?
        let writer = DenController(state: DenState(desks: [first, second], focusedDeskID: second.id)) {
            persistedState = $0
        }

        // Act
        writer.focusDesk(first.id)

        // Assert
        let restored = try #require(persistedState)
        #expect(restored == writer.state)
        #expect(restored.desks.map(\.id) == [first.id, second.id])
        #expect(restored.desks[0].boards.map(\.id) == firstBoards.map(\.id))
        #expect(restored.desks.map(\.label) == ["First", "Second"])
        #expect(restored.desks[0].boards.map(\.label) == ["One", "Two"])
        #expect(restored.desks[0].boards.map(\.width) == [440, 760])
        #expect(
            restored.desks[0].boards.map(\.currentSheetURL) == [
                URL(string: "https://one.example/path"), URL(string: "https://two.example/"),
            ])
        #expect(restored.focusedDeskID == first.id)
        #expect(restored.desks.map(\.focusedBoardID) == [firstBoards[1].id, secondBoards[0].id])
    }

    @Test func persistedStateRestoresDeskScrollOffset() throws {
        // Arrange
        let first = desk("First", boards: [board("One")])
        var persistedState: DenState?
        let writer = DenController(state: DenState(desks: [first], focusedDeskID: first.id)) {
            persistedState = $0
        }

        // Act
        writer.saveDeskScrollOffset(350.0, for: first.id)

        // Assert
        let restored = try #require(persistedState)
        #expect(restored.desks[0].scrollOffsetX == 350.0)
    }

    @Test func persistedStateClearsDeskScrollOffset() throws {
        // Arrange
        let first = desk("First", boards: [board("One")])
        var persistedState: DenState?
        let writer = DenController(state: DenState(desks: [first], focusedDeskID: first.id)) {
            persistedState = $0
        }
        writer.saveDeskScrollOffset(350.0, for: first.id)

        // Act
        writer.saveDeskScrollOffset(nil, for: first.id)

        // Assert
        let cleared = try #require(persistedState)
        #expect(cleared.desks[0].scrollOffsetX == nil)
    }

    @Test func boardAndDeskIDsKeepFoundationUUIDJSONShapeInPersistedDenState() throws {
        // Arrange
        let boardUUID = UUID()
        let deskUUID = UUID()
        let boardID = BoardID(boardUUID)
        let deskID = DeskID(deskUUID)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let persistedBoard = BoardState(
            id: boardID,
            label: "Board",
            width: 520,
            currentSheetURL: nil)
        let desk = DeskState(
            id: deskID,
            label: "Desk",
            boards: [persistedBoard],
            focusedBoardID: boardID,
            anchorBoardID: boardID)
        let state = DenState(desks: [desk], focusedDeskID: deskID)

        // Act
        let data = try encoder.encode(state)
        let decoded = try decoder.decode(DenState.self, from: data)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedDesks = try #require(object["desks"] as? [[String: Any]])
        let encodedDesk = try #require(encodedDesks.first)
        let encodedBoards = try #require(encodedDesk["boards"] as? [[String: Any]])
        let encodedBoard = try #require(encodedBoards.first)

        // Assert
        #expect(object["focusedDeskID"] as? String == deskUUID.uuidString)
        #expect(encodedDesk["id"] as? String == deskUUID.uuidString)
        #expect(encodedDesk["focusedBoardID"] as? String == boardUUID.uuidString)
        #expect(encodedDesk["anchorBoardID"] as? String == boardUUID.uuidString)
        #expect(encodedBoard["id"] as? String == boardUUID.uuidString)
        #expect(decoded == state)
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: BoardID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
