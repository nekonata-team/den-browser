import AppKit
import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DeskFilterModelTests {
    @Test func filteringMatchesBoardLabelAndCurrentSheetURLWithoutChangingFocus() {
        let alpha = board("Alpha", url: "https://search.example/")
        let bravo = board("Bravo", url: "https://github.com/example/repository")
        let charlie = board("Charlie", url: "https://docs.example/")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: bravo.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }

        windowModel.deskFilter.enter()
        windowModel.deskFilter.setQuery("char")

        #expect(windowModel.deskFilter.filteredBoards.map(\.id) == [charlie.id])
        #expect(windowModel.deskFilter.selectionBoardID == charlie.id)
        #expect(controller.focusedBoard?.id == bravo.id)

        windowModel.deskFilter.setQuery("github")

        #expect(windowModel.deskFilter.filteredBoards.map(\.id) == [bravo.id])
        #expect(windowModel.deskFilter.selectionBoardID == bravo.id)
        #expect(controller.focusedBoard?.id == bravo.id)
    }

    @Test func keyboardFilteringConfirmsQueryThenEntersSelection() async throws {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let charlie = board("Charlie")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: alpha.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        #expect(
            KeyboardController.handle(try keyEvent("/", keyCode: 44), controller: controller, windowModel: windowModel))
        #expect(windowModel.deskFilter.isPresented)
        #expect(windowModel.deskFilter.isInputActive)
        #expect(windowModel.deskFilter.phase == .filtering)

        windowModel.deskFilter.setQuery("a")
        #expect(windowModel.deskFilter.filteredBoards.map(\.id) == [alpha.id, bravo.id, charlie.id])

        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), controller: controller, windowModel: windowModel))
        #expect(!windowModel.deskFilter.isInputActive)
        #expect(windowModel.deskFilter.phase == .selecting)
        #expect(controller.focusedBoard?.id == alpha.id)

        #expect(
            KeyboardController.handle(
                try keyEvent(.rightArrow, keyCode: 124), controller: controller, windowModel: windowModel))
        #expect(windowModel.deskFilter.selectionBoardID == bravo.id)
        #expect(controller.focusedBoard?.id == alpha.id)

        #expect(
            KeyboardController.handle(
                try keyEvent(.carriageReturn, keyCode: 36), controller: controller, windowModel: windowModel))
        #expect(controller.focusedBoard?.id == bravo.id)
        let centerDeadline = ContinuousClock.now + .seconds(2)
        while windowModel.centerFocusedBoardRequest == 0, ContinuousClock.now < centerDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(windowModel.centerFocusedBoardRequest == 1)
        #expect(!windowModel.deskFilter.isPresented)
        #expect(windowModel.deskFilter.phase == .inactive)
        #expect(windowModel.deskFilter.query.isEmpty)
        #expect(!windowModel.isDenMode)
    }

    @Test func selectionNavigationWrapsAtBothEnds() {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let charlie = board("Charlie")
        let source = desk("Desk", boards: [alpha, bravo, charlie], focusedBoardID: alpha.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.deskFilter.enter()

        windowModel.deskFilter.selectBoard(by: -1)
        #expect(windowModel.deskFilter.selectionBoardID == charlie.id)
        windowModel.deskFilter.selectBoard(by: 1)
        #expect(windowModel.deskFilter.selectionBoardID == alpha.id)
    }

    @Test func presentingTemporaryContextCancelsPendingCentering() async throws {
        // Arrange
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let source = desk("Desk", boards: [alpha, bravo], focusedBoardID: alpha.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.deskFilter.enter()
        windowModel.deskFilter.confirmSelection(bravo.id)

        // Act
        windowModel.showOverview()
        try await Task.sleep(for: .milliseconds(70))

        // Assert
        #expect(windowModel.centerFocusedBoardRequest == 0)
    }

    @Test func deskFilterPassesShiftedCharactersToTextInput() throws {
        let alpha = board("Alpha")
        let source = desk("Desk", boards: [alpha], focusedBoardID: alpha.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.deskFilter.enter()

        let uppercase = try keyEvent(
            "A",
            keyCode: 0,
            modifiers: [.shift],
            charactersIgnoringModifiers: "a")

        #expect(!KeyboardController.handle(uppercase, controller: controller, windowModel: windowModel))
        #expect(windowModel.deskFilter.isInputActive)
    }

    @Test func deskFilterPassesModifiedReturnAndEscapeToTextInput() throws {
        let alpha = board("Alpha")
        let source = desk("Desk", boards: [alpha], focusedBoardID: alpha.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.deskFilter.enter()

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

        #expect(!KeyboardController.handle(modifiedReturn, controller: controller, windowModel: windowModel))
        #expect(!KeyboardController.handle(modifiedEscape, controller: controller, windowModel: windowModel))
        #expect(windowModel.deskFilter.isInputActive)
    }

    @Test func escapeCancelsFilterAndDeskCommandsStaySuspended() throws {
        let alpha = board("Alpha")
        let bravo = board("Bravo")
        let source = desk("Desk", boards: [alpha, bravo], focusedBoardID: alpha.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.deskFilter.enter()
        windowModel.deskFilter.setQuery("bravo")
        windowModel.deskFilter.confirmQuery()

        #expect(
            KeyboardController.handle(try keyEvent("x", keyCode: 7), controller: controller, windowModel: windowModel))
        #expect(controller.focusedDesk?.boards.map(\.id) == [alpha.id, bravo.id])

        #expect(
            KeyboardController.handle(
                try keyEvent("\u{1B}", keyCode: 53), controller: controller, windowModel: windowModel))
        #expect(!windowModel.deskFilter.isPresented)
        #expect(windowModel.deskFilter.query.isEmpty)
        #expect(controller.focusedBoard?.id == alpha.id)
        #expect(windowModel.isDenMode)
    }

    @Test func markedTextKeepsFilterInputActiveUntilIMECommits() throws {
        let alpha = board("Alpha")
        let source = desk("Desk", boards: [alpha], focusedBoardID: alpha.id)
        let controller = DenController(state: DenState(desks: [source], focusedDeskID: source.id))
        let composition = DenWindowComposition(controller: controller)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true
        windowModel.deskFilter.enter()

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

        #expect(!KeyboardController.handle(returnEvent, controller: controller, windowModel: windowModel))
        #expect(!KeyboardController.handle(escapeEvent, controller: controller, windowModel: windowModel))
        #expect(windowModel.deskFilter.isInputActive)
        #expect(windowModel.deskFilter.isPresented)

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
