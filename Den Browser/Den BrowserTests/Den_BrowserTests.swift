//
//  Den_BrowserTests.swift
//  Den BrowserTests
//
//  Created by 大澤弘明 on 2026/07/10.
//

import Testing
import Foundation
@testable import Den_Browser

@MainActor
struct Den_BrowserTests {

    @Test func createsEmptyDeskAfterFocusedDesk() {
        let first = DeskState(label: "First", boards: [])
        let second = DeskState(label: "Second", boards: [])
        let store = makeStore(desks: [first, second], focusedDeskID: first.id)

        store.createDesk(label: "  Writing  ", template: .empty)

        #expect(store.state.desks.map(\.label) == ["First", "Writing", "Second"])
        #expect(store.focusedDesk?.label == "Writing")
        #expect(store.focusedDesk?.boards.isEmpty == true)
    }

    @Test func createsChatGPTTemplateWithThreeBoards() {
        let first = DeskState(label: "First", boards: [])
        let store = makeStore(desks: [first], focusedDeskID: first.id)

        store.createDesk(label: "AI", template: .chatGPTThree)

        #expect(store.focusedDesk?.boards.count == 3)
        #expect(store.focusedDesk?.boards.allSatisfy { $0.currentURLString == "https://chatgpt.com/" } == true)
        #expect(store.focusedDesk?.boards.allSatisfy { $0.width == 520 } == true)
        #expect(store.focusedDesk?.focusedBoardID == store.focusedDesk?.boards.first?.id)
    }

    @Test func cancelingHoldKeepsDeskCreatedAfterHold() {
        let board = BoardState(label: "Source", width: 520, currentURLString: "https://example.com")
        let first = DeskState(label: "First", boards: [board])
        let store = makeStore(desks: [first], focusedDeskID: first.id)

        store.holdFocusedBoard()
        store.createDesk(label: "Destination", template: .empty)
        store.cancelHeldBoard()

        #expect(store.heldBoardID == nil)
        #expect(store.state.desks.count == 2)
        #expect(store.focusedDesk?.label == "Destination")
        #expect(store.state.desks[0].boards.first?.id == board.id)
    }

    @Test func placesHeldBoardIntoNewDesk() {
        let board = BoardState(label: "Source", width: 520, currentURLString: "https://example.com")
        let first = DeskState(label: "First", boards: [board])
        let store = makeStore(desks: [first], focusedDeskID: first.id)

        store.holdFocusedBoard()
        store.createDesk(label: "Destination", template: .empty)
        store.placeHeldBoard()

        #expect(store.heldBoardID == nil)
        #expect(store.state.desks[0].boards.isEmpty)
        #expect(store.focusedDesk?.boards.map(\.id) == [board.id])
    }

    private func makeStore(desks: [DeskState], focusedDeskID: UUID) -> DenStore {
        DenStore(
            state: DenState(desks: desks, focusedDeskID: focusedDeskID),
            persistenceURL: FileManager.default.temporaryDirectory
                .appending(path: "den-browser-tests-\(UUID().uuidString).json")
        )
    }

}
