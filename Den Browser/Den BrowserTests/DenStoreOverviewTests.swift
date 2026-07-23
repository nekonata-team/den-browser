import AppKit
import Foundation
import Testing
@testable import Den_Browser

@MainActor
struct DenStoreOverviewTests {

    @Test func commandTOpensBoardPanelFromOverview() throws {
        try withStore(desks: [desk("Desk")]) { store in
            store.showOverview()
            let event = try #require(
                NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: .command,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    characters: "t",
                    charactersIgnoringModifiers: "t",
                    isARepeat: false,
                    keyCode: 17
                ))

            #expect(KeyboardController.handle(event, store: store))
            #expect(store.isOpenBoardPanelPresented)
            #expect(!store.isOverviewPresented)
        }
    }

    @Test func temporaryContextsAreExclusiveAndClearOverviewSelection() {
        let board = board("Board")
        withStore(desks: [desk("Desk", boards: [board], focusedBoardID: board.id)]) { store in
            store.showOverview()
            #expect(store.temporaryContext == .overview)
            #expect(store.overviewSelectionBoardID == board.id)

            store.showOpenBoardPanel()

            #expect(store.temporaryContext == .openBoard)
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)
            #expect(!store.isOverviewPresented)
        }
    }

    @Test func overviewFilteringAndNavigation() {
        let b1 = board("Google", url: "https://google.com")
        let b2 = board("GitHub", url: "https://github.com")
        let desk1 = desk("Main", boards: [b1], focusedBoardID: b1.id)
        let desk2 = desk("Dev", boards: [b2], focusedBoardID: b2.id)

        withStore(desks: [desk1, desk2]) { store in
            // 1. Show overview
            store.showOverview()
            #expect(store.overviewQuery == "")
            #expect(!store.isOverviewFilterMode)
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == b1.id)

            // 2. Set query matching b2
            store.setOverviewQuery("git")
            #expect(store.overviewQuery == "git")
            // Selection should jump to first matching board (b2 in desk2)
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == b2.id)

            // 3. Re-set query matching b1
            store.setOverviewQuery("oog")
            #expect(store.overviewSelectionDeskID == desk1.id)
            #expect(store.overviewSelectionBoardID == b1.id)

            // 4. Test matchesOverviewFilter
            #expect(store.matchesOverviewFilter(b1, in: desk1))
            #expect(!store.matchesOverviewFilter(b2, in: desk2))

            // 5. Non-matching query clears selection
            store.setOverviewQuery("nonexistent")
            #expect(store.overviewSelectionDeskID == nil)
            #expect(store.overviewSelectionBoardID == nil)

            // 6. Enter filter mode, type query, and confirm it
            store.enterOverviewFilterMode()
            #expect(store.isOverviewFilterMode)
            store.setOverviewQuery("git")
            store.confirmOverviewFilterQuery()
            #expect(!store.isOverviewFilterMode)
            #expect(store.overviewQuery == "git")

            // 7. Clear query in normal mode
            store.clearOverviewQuery()
            #expect(store.overviewQuery == "")
            #expect(store.overviewSelectionDeskID == desk2.id)
            #expect(store.overviewSelectionBoardID == b2.id)

            // 8. Escape clears filter mode and query
            store.enterOverviewFilterMode()
            store.exitOverviewFilterMode()
            #expect(!store.isOverviewFilterMode)
            #expect(store.overviewQuery == "")
        }
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
