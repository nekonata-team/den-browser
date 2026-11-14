import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct DrawerKeyboardTests {
    @Test(arguments: ["n", " "])
    func drawerDenModeOpensAdditionWithoutInterceptingFilterInput(character: String) throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let model = composition.model
        composition.connect()
        defer { composition.disconnect() }
        model.openDrawer()
        model.isDenMode = true
        let initial = session.resources.state
        let keyCode: UInt16 = character == "n" ? 45 : 49
        let event = try keyEvent(characters: character, charactersIgnoringModifiers: character, keyCode: keyCode)
        let repeated = try keyEvent(
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: true,
            keyCode: keyCode
        )

        // Act / Assert
        #expect(
            KeyboardController.decision(for: repeated, session: session, windowModel: model)
                == .consume(.ignoredRepeat)
        )
        for phase in [FilterPhase.filtering, .selecting] {
            model.drawer.filterPhase = phase
            #expect(
                KeyboardController.decision(for: event, session: session, windowModel: model)
                    == (phase == .filtering ? .forward(.filterTextInput) : .consume(.exclusiveContext))
            )
        }
        model.drawer.filterPhase = .inactive
        #expect(
            KeyboardController.decision(for: event, session: session, windowModel: model)
                == .perform(.drawer(.addItem))
        )
        #expect(KeyboardController.handle(event, session: session, windowModel: model))
        #expect(model.isAddingToDrawer)
        #expect(model.isDrawerPresented)
        #expect(session.resources.state == initial)
    }

    @Test func denModeToggleRemainsAvailableInDrawer() throws {
        let preferences = try makeKeyboardTestPreferences()
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/")))
        let peekID = windowModel.drawer.expandedItemID
        let toggle = try keyEvent(
            characters: ",",
            charactersIgnoringModifiers: ",",
            modifiers: [.control],
            keyCode: 43
        )

        #expect(
            KeyboardController.handle(
                toggle,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(windowModel.isDenMode)
        #expect(windowModel.drawer.expandedItemID == peekID)

        #expect(
            KeyboardController.handle(
                toggle,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(!windowModel.isDenMode)
        #expect(windowModel.drawer.expandedItemID == peekID)
    }

    @Test func drawerPlacementDeskSelectionRoutesKeysAndCanBeCanceled() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let model = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/")))
        model.isDenMode = true
        let shiftP = try keyEvent(
            characters: "P",
            charactersIgnoringModifiers: "P",
            modifiers: [.shift],
            keyCode: 35
        )
        let plainP = try keyEvent(characters: "p", charactersIgnoringModifiers: "p", keyCode: 35)
        let repeatedShiftP = try keyEvent(
            characters: "P",
            charactersIgnoringModifiers: "P",
            modifiers: [.shift],
            isARepeat: true,
            keyCode: 35
        )
        let escape = try keyEvent(characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)
        let down = try keyEvent(characters: "j", charactersIgnoringModifiers: "j", keyCode: 38)
        let enter = try keyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)

        // Act / Assert
        #expect(
            KeyboardController.decision(for: plainP, session: session, windowModel: model)
                == .perform(.drawer(.placeSelectedItemAsBoard))
        )
        #expect(
            KeyboardController.decision(for: repeatedShiftP, session: session, windowModel: model)
                == .consume(.ignoredRepeat)
        )
        #expect(
            KeyboardController.decision(for: shiftP, session: session, windowModel: model)
                == .perform(.drawer(.choosePlacementDesk))
        )
        #expect(KeyboardController.handle(shiftP, session: session, windowModel: model))
        #expect(model.drawer.isChoosingPlacementDesk)
        for (digit, number) in [("1", 1), ("9", 9), ("0", 10)] {
            let numeric = try keyEvent(characters: digit, charactersIgnoringModifiers: digit, keyCode: 18)
            #expect(
                KeyboardController.decision(for: numeric, session: session, windowModel: model)
                    == .perform(.drawer(.placeInDeskNumber(number)))
            )
        }
        #expect(
            KeyboardController.decision(for: enter, session: session, windowModel: model)
                == .perform(.drawer(.confirmPlacementDesk))
        )
        #expect(
            KeyboardController.decision(for: down, session: session, windowModel: model)
                == .perform(.drawer(.selectPlacementDesk(1)))
        )
        #expect(KeyboardController.handle(escape, session: session, windowModel: model))
        #expect(!model.drawer.isChoosingPlacementDesk)
        #expect(model.isDrawerOpen)
        #expect(model.isDenMode)
        #expect(session.resources.state.drawerItems.count == 1)

        model.isDenMode = false
        model.chooseSelectedDrawerItemPlacementDesk()
        #expect(KeyboardController.handle(escape, session: session, windowModel: model))
        #expect(!model.drawer.isChoosingPlacementDesk)
        #expect(!model.isDenMode)
    }

    @Test func drawerCommandWDiscardsSelectedItemWithoutRemovingBoard() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://first.example/")))
        session.drawer.keepInDrawer(try #require(URL(string: "https://second.example/")))
        let selectedItemID = try #require(windowModel.drawer.selectedItemID)
        let commandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            keyCode: 13
        )

        #expect(
            KeyboardController.decision(for: commandW, session: session, windowModel: windowModel)
                == .perform(.drawer(.discardSelectedItem(focusNext: true)))
        )
        #expect(KeyboardController.handle(commandW, session: session, windowModel: windowModel))
        #expect(session.resources.state.drawerItems.count == 1)
        #expect(!session.resources.state.drawerItems.contains { $0.id == selectedItemID })
        #expect(session.navigation.focusedDesk?.boards.count == 1)
        #expect(windowModel.isDrawerOpen)

        let repeatedCommandW = try keyEvent(
            characters: "w",
            charactersIgnoringModifiers: "w",
            modifiers: [.command],
            isARepeat: true,
            keyCode: 13
        )
        #expect(
            KeyboardController.decision(for: repeatedCommandW, session: session, windowModel: windowModel)
                == .consume(.ignoredRepeat)
        )
        #expect(KeyboardController.handle(repeatedCommandW, session: session, windowModel: windowModel))
        #expect(session.resources.state.drawerItems.count == 1)
    }

    @Test func drawerControlEscapeClosesDrawerWithOrWithoutPeek() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://preview.example/")))
        let itemID = try #require(windowModel.drawer.expandedItemID)
        let controlEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.control],
            keyCode: 53
        )

        #expect(
            KeyboardController.decision(for: controlEscape, session: session, windowModel: windowModel)
                == .perform(.drawer(.close))
        )
        #expect(KeyboardController.handle(controlEscape, session: session, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == itemID)

        windowModel.openDrawer()
        windowModel.drawer.toggleItem(itemID)
        windowModel.isDenMode = true

        #expect(KeyboardController.handle(controlEscape, session: session, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
        #expect(session.resources.state.drawerItems.count == 1)
    }

    @Test func drawerConsumesUnmappedKeysWhenPeekIsNotFocused() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/")))
        let itemID = try #require(windowModel.drawer.selectedItemID)
        windowModel.drawer.toggleItem(itemID)
        #expect(!windowModel.isDenMode)
        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == nil)

        let letterA = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0
        )
        let space = try keyEvent(
            characters: " ",
            charactersIgnoringModifiers: " ",
            keyCode: 49
        )
        let tab = try keyEvent(
            characters: "\t",
            charactersIgnoringModifiers: "\t",
            keyCode: 48
        )

        #expect(
            KeyboardController.decision(for: letterA, session: session, windowModel: windowModel)
                == .consume(.exclusiveContext)
        )
        #expect(KeyboardController.handle(letterA, session: session, windowModel: windowModel))

        #expect(
            KeyboardController.decision(for: space, session: session, windowModel: windowModel)
                == .consume(.exclusiveContext)
        )
        #expect(KeyboardController.handle(space, session: session, windowModel: windowModel))

        #expect(
            KeyboardController.decision(for: tab, session: session, windowModel: windowModel)
                == .consume(.exclusiveContext)
        )
        #expect(KeyboardController.handle(tab, session: session, windowModel: windowModel))

        #expect(windowModel.isDrawerOpen)
        #expect(session.resources.state.drawerItems.count == 1)
        #expect(session.navigation.focusedDesk?.boards.count == 1)
    }

    @Test func denModeShiftDRequestsDrawerClearConfirmation() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://first.example/")))
        session.drawer.keepInDrawer(try #require(URL(string: "https://second.example/")))
        windowModel.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2
        )

        #expect(KeyboardController.handle(clear, session: session, windowModel: windowModel))
        #expect(windowModel.drawerPendingDiscardCount == 2)
        #expect(session.resources.state.drawerItems.count == 2)
    }

    @Test func drawerFKeyTogglesPresentationStyle() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.openDrawer()
        windowModel.isDenMode = true

        #expect(session.configuration.preferences.drawerStyle == .floating)

        let fKey = try keyEvent(
            characters: "f",
            charactersIgnoringModifiers: "f",
            keyCode: 3
        )
        #expect(KeyboardController.handle(fKey, session: session, windowModel: windowModel))
        #expect(session.configuration.preferences.drawerStyle == .bottom)

        #expect(KeyboardController.handle(fKey, session: session, windowModel: windowModel))
        #expect(session.configuration.preferences.drawerStyle == .floating)
    }

    @Test func denModeShiftDDoesNothingInDrawerFilterModeOrOnRepeat() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.isDenMode = true

        let clear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            keyCode: 2
        )
        windowModel.drawer.enterFilterMode()
        #expect(!KeyboardController.handle(clear, session: session, windowModel: windowModel))
        #expect(!windowModel.hasPendingConfirmation)

        windowModel.drawer.exitFilterMode()
        let repeatClear = try keyEvent(
            characters: "D",
            charactersIgnoringModifiers: "d",
            modifiers: [.shift],
            isARepeat: true,
            keyCode: 2
        )
        #expect(KeyboardController.handle(repeatClear, session: session, windowModel: windowModel))
        #expect(!windowModel.hasPendingConfirmation)
    }

    @Test func drawerFilterPassesShiftedCharactersToTextInput() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.isDenMode = true
        windowModel.drawer.enterFilterMode()

        let uppercase = try keyEvent(
            characters: "A",
            charactersIgnoringModifiers: "a",
            modifiers: [.shift],
            keyCode: 0
        )

        #expect(!KeyboardController.handle(uppercase, session: session, windowModel: windowModel))
        #expect(windowModel.drawer.isFilterInputActive)
    }

    @Test func drawerFilterPassesModifiedReturnAndControlEscapeClosesDrawer() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        session.drawer.keepInDrawer(try #require(URL(string: "https://example.com/")))
        windowModel.isDenMode = true
        windowModel.drawer.enterFilterMode()

        let modifiedReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.shift],
            keyCode: 36
        )
        let controlEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifiers: [.control],
            keyCode: 53
        )

        #expect(!KeyboardController.handle(modifiedReturn, session: session, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: controlEscape, session: session, windowModel: windowModel)
                == .perform(.drawer(.close))
        )
        #expect(KeyboardController.handle(controlEscape, session: session, windowModel: windowModel))
        #expect(!windowModel.isDrawerOpen)
    }

    @Test func denModeAMovesFocusedBoardToDrawer() throws {
        let focused = makeTestBoard("Focused", url: "https://drawer.example/")
        let session = try makeKeyboardTestSession(boards: [focused])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        windowModel.isDenMode = true

        let keep = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            keyCode: 0
        )

        #expect(
            KeyboardController.decision(for: keep, session: session, windowModel: windowModel)
                == .perform(.board(.moveBoardToDrawer))
        )
        #expect(KeyboardController.handle(keep, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedDesk?.boards.isEmpty == true)
        #expect(windowModel.isDenMode)
        #expect(session.resources.state.drawerItems.first?.url == URL(string: "https://drawer.example/"))
        #expect(!windowModel.isDrawerOpen)
    }
}
