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
struct EssentialsPrefixKeyboardTests {
    @Test func denModeGPrefixLaunchesMatchingEssential() throws {
        let session = try makeKeyboardTestSession(boards: [BoardState(label: "First", width: 720, currentSheetURL: nil)]
        )
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(session.configuration.preferences.setEssentials([essential]))
        windowModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g",
            charactersIgnoringModifiers: "g",
            keyCode: 5
        )
        let key = try keyEvent(
            characters: "c",
            charactersIgnoringModifiers: "c",
            keyCode: 8
        )

        #expect(
            KeyboardController.decision(for: prefix, session: session, windowModel: windowModel)
                == .perform(.essentials(.enterPrefix))
        )
        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == .essentialsPrefix)
        #expect(
            KeyboardController.decision(for: key, session: session, windowModel: windowModel)
                == .perform(.essentials(.launch(essential.id)))
        )
        #expect(KeyboardController.handle(key, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(!windowModel.isDenMode)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
        #expect(session.navigation.focusedBoard?.width == 720)
    }

    @Test func sheetInputEssentialsPrefixLaunchesWithoutEnteringDenMode() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(session.configuration.preferences.setEssentials([essential]))
        windowModel.showEssentialsPrefix()

        let key = try keyEvent(
            characters: "c",
            charactersIgnoringModifiers: "c",
            keyCode: 8
        )

        #expect(
            KeyboardController.decision(for: key, session: session, windowModel: windowModel)
                == .perform(.essentials(.launch(essential.id)))
        )
        #expect(KeyboardController.handle(key, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(!windowModel.isDenMode)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://chatgpt.com/"))
    }

    @Test func essentialsPrefixSelectionWrapsBetweenFirstAndLast() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(session.configuration.preferences.setEssentials([first, second]))

        // Act
        windowModel.showEssentialsPrefix()
        windowModel.moveEssentialSelection(by: -1)

        // Assert
        #expect(windowModel.selectedEssentialID == second.id)

        // Act
        windowModel.moveEssentialSelection(by: 1)

        // Assert
        #expect(windowModel.selectedEssentialID == first.id)
    }

    @Test func essentialsPrefixOpeningResetsSelectionToFirst() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(session.configuration.preferences.setEssentials([first, second]))
        windowModel.showEssentialsPrefix()

        // Act
        windowModel.moveEssentialSelection(by: 1)
        windowModel.exitEssentialsPrefix()
        windowModel.showEssentialsPrefix()

        // Assert
        #expect(windowModel.selectedEssentialID == first.id)
    }

    @Test func essentialsPrefixReturnLaunchesFocusedEssentialAndClosesPrefix() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First Essential", key: "a", input: "https://first.example")
        let second = Essential(name: "Second Essential", key: "b", input: "https://second.example")
        #expect(session.configuration.preferences.setEssentials([first, second]))
        windowModel.showEssentialsPrefix()

        // Act
        windowModel.moveEssentialSelection(by: 1)
        windowModel.launchSelectedEssential()

        // Assert
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.selectedEssentialID == nil)
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://second.example/"))
    }

    @Test(arguments: ["https://drawer.example", "Swift concurrency"])
    func essentialsPrefixOptionReturnOpensSelectedWebInputInDrawer(input: String) throws {
        // Arrange
        let original = makeTestBoard("First")
        let session = try makeKeyboardTestSession(boards: [original])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First", key: "a", input: "https://first.example")
        let selected = Essential(name: "Selected", key: "b", input: input)
        #expect(session.configuration.preferences.setEssentials([first, selected]))
        windowModel.showEssentialsPrefix()
        windowModel.moveEssentialSelection(by: 1)
        let event = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.option],
            keyCode: 36
        )

        // Act
        let handled = KeyboardController.handle(event, session: session, windowModel: windowModel)

        // Assert
        #expect(handled)
        let item = try #require(session.resources.state.drawerItems.first)
        #expect(
            WebURLPolicy.canonicalSheetURL(try #require(item.url))
                == BoardInputResolver.normalizedURL(
                    from: input,
                    searchEngine: session.configuration.preferences.searchEngine
                )
        )
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [original.id])
        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == item.id)
        #expect(windowModel.selectedEssentialID == nil)
    }

    @Test(arguments: ["c", "C", " "])
    func essentialsPrefixOptionKeyOpensMatchingEssentialInDrawer(key: String) throws {
        // Arrange
        let original = makeTestBoard("First")
        let session = try makeKeyboardTestSession(boards: [original])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let first = Essential(name: "First", key: "a", input: "https://first.example")
        let matching = Essential(name: "Matching", key: key, input: "https://drawer.example")
        let otherCase = Essential(name: "Other case", key: key == "C" ? "c" : "C", input: "https://other.example")
        #expect(session.configuration.preferences.setEssentials([first, matching, otherCase]))
        windowModel.showEssentialsPrefix()
        let event = try keyEvent(
            characters: key == " " ? " " : "ç",
            charactersIgnoringModifiers: key,
            modifiers: key == "C" ? [.option, .shift] : [.option],
            keyCode: key == " " ? 49 : 8
        )

        // Act
        let decision = KeyboardController.decision(for: event, session: session, windowModel: windowModel)
        let handled = KeyboardController.handle(event, session: session, windowModel: windowModel)

        // Assert
        #expect(decision == .perform(.essentials(.launchInDrawer(matching.id))))
        #expect(handled)
        let item = try #require(session.resources.state.drawerItems.first)
        #expect(item.url?.host == "drawer.example")
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [original.id])
        #expect(windowModel.isDrawerOpen)
        #expect(windowModel.drawer.expandedItemID == item.id)
        #expect(windowModel.selectedEssentialID == nil)
    }

    @Test func essentialsPrefixOptionReturnRejectsBoardCommands() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "Tutorial", key: "t", input: ":tutorial")
        #expect(session.configuration.preferences.setEssentials([essential]))
        windowModel.showEssentialsPrefix()

        // Act
        windowModel.launchSelectedEssential(inDrawer: true)

        // Assert
        #expect(session.resources.state.drawerItems.isEmpty)
        #expect(session.navigation.focusedDesk?.boards.count == 1)
        #expect(session.feedback.latest?.severity == .warning)
        #expect(windowModel.temporaryContext == nil)
    }

    @Test func drawerDenModeGOpensEssentialsPrefixInDrawerAndEscapeRestoresDrawer() throws {
        let existingURL = try #require(URL(string: "https://existing.example"))
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let existingItemID = try #require(session.drawer.keepInDrawer(existingURL, opensDrawer: false))
        let essential = Essential(name: "Docs", key: "d", input: "https://docs.example")
        #expect(session.configuration.preferences.setEssentials([essential]))

        windowModel.openDrawer()
        windowModel.drawer.setQuery("existing")
        windowModel.isDenMode = true

        let prefix = try keyEvent(characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        #expect(
            KeyboardController.decision(for: prefix, session: session, windowModel: windowModel)
                == .perform(.essentials(.enterPrefix))
        )
        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == .essentialsPrefix)
        #expect(windowModel.essentialsPrefixOpensInDrawer)
        #expect(windowModel.isAddingEssentialToDrawer)
        #expect(windowModel.isDrawerPresented)

        let escape = try keyEvent(characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53)
        #expect(KeyboardController.handle(escape, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == .drawer)
        #expect(!windowModel.essentialsPrefixOpensInDrawer)
        #expect(windowModel.drawer.selectedItemID == existingItemID)
        #expect(windowModel.drawer.query == "existing")
    }

    @Test func drawerEssentialsPrefixLaunchesMatchingKeyInDrawer() throws {
        let original = makeTestBoard("First")
        let session = try makeKeyboardTestSession(boards: [original])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(session.configuration.preferences.setEssentials([essential]))

        windowModel.openDrawer()
        windowModel.isDenMode = true

        let prefix = try keyEvent(characters: "g", charactersIgnoringModifiers: "g", keyCode: 5)
        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))

        let key = try keyEvent(characters: "c", charactersIgnoringModifiers: "c", keyCode: 8)
        #expect(KeyboardController.handle(key, session: session, windowModel: windowModel))

        let item = try #require(session.resources.state.drawerItems.first)
        #expect(item.url?.host == "chatgpt.com")
        #expect(session.navigation.focusedDesk?.boards.map(\.id) == [original.id])
        #expect(windowModel.isDrawerOpen)
        #expect(!windowModel.essentialsPrefixOpensInDrawer)
        #expect(windowModel.drawer.expandedItemID == item.id)
    }

    @Test func essentialsPrefixRoutesArrowsReturnAndConfiguredJkKeys() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let jEssential = Essential(name: "J Essential", key: "j", input: "https://j.example")
        let kEssential = Essential(name: "K Essential", key: "k", input: "https://k.example")
        #expect(session.configuration.preferences.setEssentials([jEssential, kEssential]))
        windowModel.showEssentialsPrefix()
        let upArrow = try arrowEvent(.upArrow, modifiers: [])
        let down = try arrowEvent(.downArrow, modifiers: [])
        let returnKey = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )
        let optionReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.option],
            keyCode: 36
        )
        let jKey = try keyEvent(characters: "j", charactersIgnoringModifiers: "j", keyCode: 38)
        let kKey = try keyEvent(characters: "k", charactersIgnoringModifiers: "k", keyCode: 40)

        // Act
        func route(_ event: NSEvent) -> InputDecision {
            KeyboardRouter.route(
                event: KeyEvent(event),
                context: InputContext(session: session, windowModel: windowModel, event: event),
                shortcuts: ShortcutConfiguration(preferences: session.configuration.preferences)
            )
        }
        let upDecision = route(upArrow)
        let downDecision = route(down)
        let returnDecision = route(returnKey)
        let optionReturnDecision = route(optionReturn)
        let jDecision = route(jKey)
        let kDecision = route(kKey)

        // Assert
        #expect(upDecision == .perform(.essentials(.moveSelection(-1))))
        #expect(downDecision == .perform(.essentials(.moveSelection(1))))
        #expect(returnDecision == .perform(.essentials(.launchSelected)))
        #expect(optionReturnDecision == .perform(.essentials(.launchSelectedInDrawer)))
        #expect(jDecision == .perform(.essentials(.launch(jEssential.id))))
        #expect(kDecision == .perform(.essentials(.launch(kEssential.id))))
    }

    @Test func essentialsPrefixAllowsRepeatedArrowMovementButSuppressesRepeatedLaunch() throws {
        // Arrange
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "Essential", key: "a", input: "https://essential.example")
        let nextEssential = Essential(name: "Next", key: "b", input: "https://next.example")
        #expect(session.configuration.preferences.setEssentials([essential, nextEssential]))
        windowModel.showEssentialsPrefix()
        let repeatedUp = try arrowEvent(.upArrow, modifiers: [], isARepeat: true)
        let repeatedDown = try arrowEvent(.downArrow, modifiers: [], isARepeat: true)
        let repeatedReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: true,
            keyCode: 36
        )
        let repeatedOptionReturn = try keyEvent(
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            modifiers: [.option],
            isARepeat: true,
            keyCode: 36
        )
        let repeatedKey = try keyEvent(
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: true,
            keyCode: 0
        )
        let repeatedEscape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: true,
            keyCode: 53
        )
        func route(_ event: NSEvent) -> InputDecision {
            KeyboardRouter.route(
                event: KeyEvent(event),
                context: InputContext(session: session, windowModel: windowModel, event: event),
                shortcuts: ShortcutConfiguration(preferences: session.configuration.preferences)
            )
        }

        // Act
        let upDecision = route(repeatedUp)
        let movementDecision = route(repeatedDown)
        let returnDecision = route(repeatedReturn)
        let optionReturnDecision = route(repeatedOptionReturn)
        let keyDecision = route(repeatedKey)
        let escapeDecision = route(repeatedEscape)
        #expect(KeyboardController.handle(repeatedDown, session: session, windowModel: windowModel))
        #expect(KeyboardController.handle(repeatedReturn, session: session, windowModel: windowModel))
        #expect(KeyboardController.handle(repeatedKey, session: session, windowModel: windowModel))

        // Assert
        #expect(upDecision == .perform(.essentials(.moveSelection(-1))))
        #expect(movementDecision == .perform(.essentials(.moveSelection(1))))
        #expect(windowModel.selectedEssentialID == nextEssential.id)
        #expect(returnDecision == .consume(.ignoredRepeat))
        #expect(optionReturnDecision == .consume(.ignoredRepeat))
        #expect(keyDecision == .consume(.ignoredRepeat))
        #expect(escapeDecision == .consume(.ignoredRepeat))
        #expect(session.navigation.focusedDesk?.boards.count == 1)
    }

    @Test func denModeGPrefixShowsFeedbackForUnregisteredKeys() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let essential = Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
        #expect(session.configuration.preferences.setEssentials([essential]))
        windowModel.isDenMode = true
        let prefix = try keyEvent(
            characters: "g",
            charactersIgnoringModifiers: "g",
            keyCode: 5
        )
        let unknown = try keyEvent(
            characters: "x",
            charactersIgnoringModifiers: "x",
            keyCode: 7
        )

        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: unknown, session: session, windowModel: windowModel)
                == .perform(.essentials(.showNotFound("x")))
        )
        #expect(KeyboardController.handle(unknown, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)
        #expect(session.navigation.focusedDesk?.boards.count == 1)
        #expect(session.feedback.latest?.message == "No Essential assigned to 'x'.")
        #expect(session.feedback.latest?.severity == .warning)
    }

    @Test func denModeGPrefixCancelsQuietlyForEscapeAndModifiedKeys() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        #expect(
            session.configuration.preferences.setEssentials([
                Essential(name: "ChatGPT", key: "c", input: "https://chatgpt.com")
            ])
        )
        windowModel.isDenMode = true
        let prefix = try keyEvent(
            characters: "g",
            charactersIgnoringModifiers: "g",
            keyCode: 5
        )
        let escape = try keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )
        let modified = try keyEvent(
            characters: "x",
            charactersIgnoringModifiers: "x",
            modifiers: [.command],
            keyCode: 7
        )

        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))
        #expect(KeyboardController.handle(escape, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)

        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))
        #expect(KeyboardController.handle(modified, session: session, windowModel: windowModel))
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)
        #expect(session.feedback.latest == nil)
    }

    @Test func denModeGPrefixPreservesEssentialKeyCase() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let lowercase = Essential(name: "Lowercase", key: "c", input: "https://example.com/lower")
        let uppercase = Essential(name: "Uppercase", key: "C", input: "https://example.com/upper")
        #expect(session.configuration.preferences.setEssentials([lowercase, uppercase]))
        windowModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g",
            charactersIgnoringModifiers: "g",
            keyCode: 5
        )
        let lowercaseKey = try keyEvent(
            characters: "c",
            charactersIgnoringModifiers: "c",
            keyCode: 8
        )
        let uppercaseKey = try keyEvent(
            characters: "C",
            charactersIgnoringModifiers: "c",
            modifiers: [.shift],
            keyCode: 8
        )

        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))
        #expect(
            KeyboardController.decision(for: lowercaseKey, session: session, windowModel: windowModel)
                == .perform(.essentials(.launch(lowercase.id)))
        )
        #expect(
            KeyboardController.decision(for: uppercaseKey, session: session, windowModel: windowModel)
                == .perform(.essentials(.launch(uppercase.id)))
        )
        #expect(KeyboardController.handle(uppercaseKey, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedBoard?.currentSheetURL == URL(string: "https://example.com/upper"))
    }

    @Test func denModeGPrefixCanLaunchTerminalEssential() throws {
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(
            session.configuration.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal \(directory)")
            ])
        )
        windowModel.isDenMode = true

        let prefix = try keyEvent(
            characters: "g",
            charactersIgnoringModifiers: "g",
            keyCode: 5
        )
        let key = try keyEvent(
            characters: "t",
            charactersIgnoringModifiers: "t",
            keyCode: 17
        )

        #expect(KeyboardController.handle(prefix, session: session, windowModel: windowModel))
        #expect(KeyboardController.handle(key, session: session, windowModel: windowModel))
        #expect(session.navigation.focusedBoard?.terminalWorkingDirectory == directory)
        #expect(!windowModel.isDenMode)
    }

    @Test func commandShortcutRemainsOutsideEssentialsPrefix() throws {
        let preferences = try makeKeyboardTestPreferences()
        let session = try makeKeyboardTestSession(boards: [makeTestBoard("First")])
        let composition = DenWindowComposition(session: session)
        let windowModel = composition.model
        composition.connect()
        defer { composition.disconnect() }
        #expect(
            session.configuration.preferences.setEssentials([
                Essential(name: "Terminal", key: "t", input: ":terminal")
            ])
        )
        windowModel.isDenMode = true
        let commandT = try keyEvent(
            characters: "t",
            charactersIgnoringModifiers: "t",
            modifiers: [.command],
            keyCode: 17
        )

        #expect(
            !KeyboardController.handle(
                commandT,
                session: session,
                windowModel: windowModel,
                preferences: preferences
            )
        )
        #expect(windowModel.temporaryContext == nil)
        #expect(windowModel.isDenMode)
    }
}
