import AppKit
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenStoreDeskFilterTests {
    @Test func filteringMatchesBoardLabelAndCurrentSheetURLWithoutChangingFocus() {
        let alpha = board("Alpha", url: "https://search.example/")
        let bravo = board("Bravo", url: "https://github.com/example/repository")
        let charlie = board("Charlie", url: "https://docs.example/")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: bravo.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))

        store.enterDeskFilter()
        store.setDeskFilterQuery("char")

        #expect(store.filteredDeskBoards.map(\.id) == [charlie.id])
        #expect(store.deskFilterSelectionBoardID == charlie.id)
        #expect(store.focusedBoard?.id == bravo.id)

        store.setDeskFilterQuery("github")

        #expect(store.filteredDeskBoards.map(\.id) == [bravo.id])
        #expect(store.deskFilterSelectionBoardID == bravo.id)
        #expect(store.focusedBoard?.id == bravo.id)
    }

    @Test func keyboardFilteringConfirmsQueryThenEntersSelection() throws {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let charlie = board("Charlie")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.isDenMode = true

        #expect(KeyboardController.handle(try keyEvent("/", keyCode: 44), store: store))
        #expect(store.isDeskFilterPresented)
        #expect(store.isDeskFilterInputActive)
        #expect(store.deskFilterPhase == .filtering)

        store.setDeskFilterQuery("a")
        #expect(store.filteredDeskBoards.map(\.id) == [alpha.id, bravo.id, charlie.id])

        #expect(KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store))
        #expect(!store.isDeskFilterInputActive)
        #expect(store.deskFilterPhase == .selecting)
        #expect(store.focusedBoard?.id == alpha.id)

        #expect(KeyboardController.handle(try keyEvent(.rightArrow, keyCode: 124), store: store))
        #expect(store.deskFilterSelectionBoardID == bravo.id)
        #expect(store.focusedBoard?.id == alpha.id)

        #expect(KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store))
        #expect(store.focusedBoard?.id == bravo.id)
        #expect(!store.isDeskFilterPresented)
        #expect(store.deskFilterPhase == .inactive)
        #expect(store.deskFilterQuery.isEmpty)
        #expect(!store.isDenMode)
    }

    @Test func escapeCancelsFilterAndDeskCommandsStaySuspended() throws {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let source = desk("Desk", boards: [alpha, bravo], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.isDenMode = true
        store.enterDeskFilter()
        store.setDeskFilterQuery("bravo")
        store.confirmDeskFilterQuery()

        #expect(KeyboardController.handle(try keyEvent("x", keyCode: 7), store: store))
        #expect(store.focusedDesk?.boards.map(\.id) == [alpha.id, bravo.id])

        #expect(KeyboardController.handle(try keyEvent("\u{1B}", keyCode: 53), store: store))
        #expect(!store.isDeskFilterPresented)
        #expect(store.deskFilterQuery.isEmpty)
        #expect(store.focusedBoard?.id == alpha.id)
        #expect(store.isDenMode)
    }

    @Test func markedTextKeepsFilterInputActiveUntilIMECommits() throws {
        let alpha = board("Alpha")
        let source = desk("Desk", boards: [alpha], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        store.isDenMode = true
        store.enterDeskFilter()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        let textView = NSTextView(frame: window.contentView?.bounds ?? .zero)
        window.contentView?.addSubview(textView)
        #expect(window.makeFirstResponder(textView))
        textView.setMarkedText(
            "にほん",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textView.hasMarkedText())
        #expect(TextInputComposition.isActive(in: window))

        let returnEvent = try keyEvent(
            String(try #require(UnicodeScalar(NSEvent.SpecialKey.carriageReturn.rawValue))),
            keyCode: 36,
            windowNumber: window.windowNumber)
        let escapeEvent = try keyEvent("\u{1B}", keyCode: 53, windowNumber: window.windowNumber)

        #expect(!KeyboardController.handle(returnEvent, store: store))
        #expect(!KeyboardController.handle(escapeEvent, store: store))
        #expect(store.isDeskFilterInputActive)
        #expect(store.isDeskFilterPresented)

        var didPerform = false
        TextInputComposition.performUnlessActive(in: window) {
            didPerform = true
        }
        #expect(!didPerform)

        textView.unmarkText()
        #expect(!TextInputComposition.isActive(in: window))
        TextInputComposition.performUnlessActive(in: window) {
            didPerform = true
        }
        #expect(didPerform)
    }

    private func keyEvent(_ specialKey: NSEvent.SpecialKey, keyCode: UInt16) throws -> NSEvent {
        let scalar = try #require(UnicodeScalar(specialKey.rawValue))
        return try keyEvent(String(scalar), keyCode: keyCode)
    }

    private func keyEvent(
        _ character: String,
        keyCode: UInt16,
        windowNumber: Int = 0
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: keyCode
            ))
    }

    private func board(_ label: String, url: String = "https://example.com/") -> BoardState {
        BoardState(label: label, width: 520, currentSheetURL: URL(string: url))
    }

    private func desk(
        _ label: String,
        boards: [BoardState],
        focusedBoardID: UUID?
    ) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }
}
