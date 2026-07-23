import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStorePersistenceTests {

    @Test func sheetScaleAppliesToNewAndLiveBoardRuntimes() {
        let suiteName = "SheetScaleTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferences(defaults: defaults)
        preferences.setSheetScale(80)
        let sheetNavigation = SheetNavigationManager(preferences: preferences)
        let board = board("Board")
        let source = desk("Desk", boards: [board], focusedBoardID: board.id)
        let store = DenStore(
            state: DenState(desks: [source], focusedDeskID: source.id),
            sheetNavigation: sheetNavigation)

        let runtime = store.runtime(for: board)
        #expect(runtime.webView.pageZoom == 0.8)

        preferences.setSheetScale(90)
        store.applySheetScale(preferences.sheetScale)
        #expect(runtime.webView.pageZoom == 0.9)
    }

    @Test func emptyPersistedDenRecoversAndSavesOneDesk() {
        var savedState: DenState?
        let store = DenStore(
            state: DenState(desks: [], focusedDeskID: UUID()),
            onSave: { savedState = $0 })

        #expect(store.state.desks.count == 1)
        #expect(store.focusedDesk != nil)
        #expect(savedState == store.state)
    }

    @Test func persistedStateRestoresDeskAndBoardDataAndFocus() throws {
        let firstBoards = [
            board("One", width: 440, url: "https://one.example/path"),
            board("Two", width: 760, url: "https://two.example/"),
        ]
        let secondBoards = [board("Three", width: 980, url: "https://three.example/query?q=1")]
        let first = desk("First", boards: firstBoards, focusedBoardID: firstBoards[1].id)
        let second = desk("Second", boards: secondBoards, focusedBoardID: secondBoards[0].id)
        var persistedState: DenState?
        let writer = DenStore(state: DenState(desks: [first, second], focusedDeskID: second.id)) {
            persistedState = $0
        }

        writer.focusDesk(first.id)
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

    private func withStore(desks: [DeskState], body: (DenStore) throws -> Void) rethrows {
        let store = DenStore(state: DenState(desks: desks, focusedDeskID: desks[0].id))
        try body(store)
    }

    private func desk(_ label: String, boards: [BoardState] = [], focusedBoardID: UUID? = nil) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }

    private func board(_ label: String, width: Double = 520, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
    }
}
