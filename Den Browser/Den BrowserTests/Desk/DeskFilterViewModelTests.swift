import AppKit
import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DeskFilterViewModelTests {
    @Test func filteringMatchesBoardLabelAndCurrentSheetURLWithoutChangingFocus() {
        let alpha = board("Alpha", url: "https://search.example/")
        let bravo = board("Bravo", url: "https://github.com/example/repository")
        let charlie = board("Charlie", url: "https://docs.example/")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: bravo.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }

        viewModel.deskFilter.enter()
        viewModel.deskFilter.setQuery("char")

        #expect(viewModel.deskFilter.filteredBoards.map(\.id) == [charlie.id])
        #expect(viewModel.deskFilter.selectionBoardID == charlie.id)
        #expect(store.focusedBoard?.id == bravo.id)

        viewModel.deskFilter.setQuery("github")

        #expect(viewModel.deskFilter.filteredBoards.map(\.id) == [bravo.id])
        #expect(viewModel.deskFilter.selectionBoardID == bravo.id)
        #expect(store.focusedBoard?.id == bravo.id)
    }

    @Test func keyboardFilteringConfirmsQueryThenEntersSelection() async throws {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let charlie = board("Charlie")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true

        #expect(KeyboardController.handle(try keyEvent("/", keyCode: 44), store: store, viewModel: viewModel))
        #expect(viewModel.deskFilter.isPresented)
        #expect(viewModel.deskFilter.isInputActive)
        #expect(viewModel.deskFilter.phase == .filtering)

        viewModel.deskFilter.setQuery("a")
        #expect(viewModel.deskFilter.filteredBoards.map(\.id) == [alpha.id, bravo.id, charlie.id])

        #expect(
            KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store, viewModel: viewModel))
        #expect(!viewModel.deskFilter.isInputActive)
        #expect(viewModel.deskFilter.phase == .selecting)
        #expect(store.focusedBoard?.id == alpha.id)

        #expect(KeyboardController.handle(try keyEvent(.rightArrow, keyCode: 124), store: store, viewModel: viewModel))
        #expect(viewModel.deskFilter.selectionBoardID == bravo.id)
        #expect(store.focusedBoard?.id == alpha.id)

        #expect(
            KeyboardController.handle(try keyEvent(.carriageReturn, keyCode: 36), store: store, viewModel: viewModel))
        #expect(store.focusedBoard?.id == bravo.id)
        let centerDeadline = ContinuousClock.now + .seconds(2)
        while viewModel.centerFocusedBoardRequest == 0, ContinuousClock.now < centerDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.centerFocusedBoardRequest == 1)
        #expect(!viewModel.deskFilter.isPresented)
        #expect(viewModel.deskFilter.phase == .inactive)
        #expect(viewModel.deskFilter.query.isEmpty)
        #expect(!viewModel.isDenMode)
    }

    @Test func selectionNavigationWrapsAtBothEnds() {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let charlie = board("Charlie")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.deskFilter.enter()

        viewModel.deskFilter.selectBoard(by: -1)
        #expect(viewModel.deskFilter.selectionBoardID == charlie.id)
        viewModel.deskFilter.selectBoard(by: 1)
        #expect(viewModel.deskFilter.selectionBoardID == alpha.id)
    }

    @Test func presentingTemporaryContextCancelsPendingCentering() async throws {
        // Arrange
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let source = desk("Desk", boards: [alpha, bravo], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.deskFilter.enter()
        viewModel.deskFilter.confirmSelection(bravo.id)

        // Act
        viewModel.showOverview()
        try await Task.sleep(for: .seconds(1))

        // Assert
        #expect(viewModel.centerFocusedBoardRequest == 0)
    }

    @Test func deskFilterPassesShiftedCharactersToTextInput() throws {
        let alpha = board("Alpha")
        let source = desk("Desk", boards: [alpha], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.deskFilter.enter()

        let uppercase = try keyEvent(
            "A",
            keyCode: 0,
            modifiers: [.shift],
            charactersIgnoringModifiers: "a")

        #expect(!KeyboardController.handle(uppercase, store: store, viewModel: viewModel))
        #expect(viewModel.deskFilter.isInputActive)
    }

    @Test func deskFilterPassesModifiedReturnAndEscapeToTextInput() throws {
        let alpha = board("Alpha")
        let source = desk("Desk", boards: [alpha], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.deskFilter.enter()

        let modifiedReturn = try keyEvent(
            "\r",
            keyCode: 36,
            modifiers: [.shift],
            charactersIgnoringModifiers: "\r")
        let modifiedEscape = try keyEvent(
            "\u{1B}",
            keyCode: 53,
            modifiers: [.command],
            charactersIgnoringModifiers: "\u{1B}")

        #expect(!KeyboardController.handle(modifiedReturn, store: store, viewModel: viewModel))
        #expect(!KeyboardController.handle(modifiedEscape, store: store, viewModel: viewModel))
        #expect(viewModel.deskFilter.isInputActive)
    }

    @Test func escapeCancelsFilterAndDeskCommandsStaySuspended() throws {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let source = desk("Desk", boards: [alpha, bravo], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.deskFilter.enter()
        viewModel.deskFilter.setQuery("bravo")
        viewModel.deskFilter.confirmQuery()

        #expect(KeyboardController.handle(try keyEvent("x", keyCode: 7), store: store, viewModel: viewModel))
        #expect(store.focusedDesk?.boards.map(\.id) == [alpha.id, bravo.id])

        #expect(KeyboardController.handle(try keyEvent("\u{1B}", keyCode: 53), store: store, viewModel: viewModel))
        #expect(!viewModel.deskFilter.isPresented)
        #expect(viewModel.deskFilter.query.isEmpty)
        #expect(store.focusedBoard?.id == alpha.id)
        #expect(viewModel.isDenMode)
    }

    @Test func markedTextKeepsFilterInputActiveUntilIMECommits() throws {
        let alpha = board("Alpha")
        let source = desk("Desk", boards: [alpha], focusedBoardID: alpha.id)
        let store = DenStore(state: DenState(desks: [source], focusedDeskID: source.id))
        let viewModel = DenViewModel(store: store)
        viewModel.connect()
        defer { viewModel.disconnect() }
        viewModel.isDenMode = true
        viewModel.deskFilter.enter()

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

        #expect(!KeyboardController.handle(returnEvent, store: store, viewModel: viewModel))
        #expect(!KeyboardController.handle(escapeEvent, store: store, viewModel: viewModel))
        #expect(viewModel.deskFilter.isInputActive)
        #expect(viewModel.deskFilter.isPresented)

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
        modifiers: NSEvent.ModifierFlags = [],
        charactersIgnoringModifiers: String? = nil,
        windowNumber: Int = 0
    ) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: windowNumber,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: charactersIgnoringModifiers ?? character,
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
        focusedBoardID: BoardID?
    ) -> DeskState {
        DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
    }
}
