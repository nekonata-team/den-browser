import AppKit
import Foundation

private struct KeyboardInput {
    let character: String?
    let baseCharacter: String?
    let characters: String?
    let key: ShortcutKey?
    let modifiers: ShortcutModifiers
    let isRepeat: Bool
    let hasMarkedText: Bool
    let isDrawerPreviewFirstResponder: Bool
    let isEscape: Bool

    var binding: ShortcutBinding? {
        guard let key else { return nil }
        return ShortcutBinding(key: key, modifiers: modifiers)
    }

    init(
        character: String?,
        baseCharacter: String?,
        characters: String? = nil,
        key: ShortcutKey?,
        modifiers: ShortcutModifiers,
        isRepeat: Bool,
        hasMarkedText: Bool = false,
        isDrawerPreviewFirstResponder: Bool = false,
        isEscape: Bool = false
    ) {
        self.character = character
        self.baseCharacter = baseCharacter
        self.characters = characters ?? character
        self.key = key
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.hasMarkedText = hasMarkedText
        self.isDrawerPreviewFirstResponder = isDrawerPreviewFirstResponder
        self.isEscape = isEscape
    }

    init(_ event: NSEvent, store: DenStore? = nil) {
        self.init(
            character: event.charactersIgnoringModifiers,
            baseCharacter: event.characters(byApplyingModifiers: []),
            characters: event.characters,
            key: ShortcutKey(event: event),
            modifiers: ShortcutModifiers(event.modifierFlags),
            isRepeat: event.isARepeat,
            hasMarkedText: TextInputComposition.isActive(in: event.window),
            isDrawerPreviewFirstResponder: store.map {
                Self.isDrawerPreviewFirstResponder(event, store: $0)
            } ?? false,
            isEscape: event.keyCode == 53)
    }

    private static func isDrawerPreviewFirstResponder(_ event: NSEvent, store: DenStore) -> Bool {
        guard
            let webView = store.drawerPreviewRuntime?.webView,
            var view = event.window?.firstResponder as? NSView
        else { return false }

        while view !== webView {
            guard let superview = view.superview else { return false }
            view = superview
        }
        return true
    }
}

@MainActor
final class KeyboardController {
    private var monitor: Any?

    func start(profileManager: ProfileManager, preferences: AppPreferences) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak profileManager, weak preferences] event in
            guard let store = profileManager?.store(for: event.window), let preferences else { return event }
            return Self.handle(event, store: store, preferences: preferences) ? nil : event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    static func handle(_ event: NSEvent, store: DenStore, preferences: AppPreferences? = nil) -> Bool {
        handle(KeyboardInput(event, store: store), store: store, preferences: preferences)
    }

    private static func handle(
        _ event: KeyboardInput,
        store: DenStore,
        preferences: AppPreferences? = nil
    ) -> Bool {
        if store.isFullscreenActive {
            return false
        }

        let modifiers = normalizedModifiers(for: event)
        let character = characterIgnoringModifiers(for: event)

        if character == "q", modifiers == [.command] {
            return false
        }

        if store.hasPendingConfirmation {
            return false
        }

        if store.isDrawerOpen,
            handleDrawerDenModeToggle(event, store: store, preferences: preferences)
        {
            return true
        }

        if store.isBoardDragging {
            if isEscape(event), modifiers == [] {
                store.requestBoardDragCancellation()
            }
            return true
        }

        if store.isDeskDragging {
            if isEscape(event), modifiers == [] {
                store.requestDeskDragCancellation()
            }
            return true
        }

        if character == "w", modifiers == [.command, .shift] {
            return false
        }

        switch store.temporaryContext {
        case .keyboardShortcuts:
            if (isEscape(event) && modifiers == [])
                || isQuestionMark(event, modifiers: modifiers)
            {
                store.hideKeyboardShortcuts()
            }
            return true
        case .boardWidth:
            return handleBoardWidthPanel(event, store: store)
        case .overview:
            return handleOverview(event, store: store)
        case .drawer:
            return handleDrawer(event, store: store)
        case .openBoard, .editBoardLink, .newDesk, .replaceDesk, .deskPresetManagement, .saveDeskPreset, .renameBoard,
            .renameDesk:
            return false
        case nil:
            break
        }

        if let character, ["l", "t", "w"].contains(character), modifiers == [.command] {
            return false
        }

        if !store.isDenMode,
            let deskNumberBinding = preferences?.deskNumberBinding,
            modifiers == deskNumberBinding.modifiers,
            let digit = baseCharacter(for: event).flatMap(Int.init),
            (0...9).contains(digit)
        {
            store.focusDesk(number: digit == 0 ? 10 : digit)
            return true
        }

        if !store.isDenMode, character == "r", modifiers == [.command] {
            return false
        }

        if character == "r", modifiers == [.command, .shift] {
            if !event.isRepeat {
                store.reloadFocusedBoardFromOrigin()
            }
            return true
        }

        if character == "r", modifiers == [.command, .option, .shift] {
            if !event.isRepeat {
                store.reloadFocusedDeskSheets()
            }
            return true
        }

        if store.isDenMode, store.isDeskFilterPresented {
            return handleDenMode(event, store: store)
        }

        if store.isDenMode,
            store.temporaryContext == nil,
            character == ",",
            modifiers == []
        {
            return false
        }

        if handleCustomShortcut(event, store: store, preferences: preferences) {
            return true
        }

        if store.isDenMode {
            return handleDenMode(event, store: store)
        }

        return false
    }

    private static func handleCustomShortcut(
        _ event: KeyboardInput,
        store: DenStore,
        preferences: AppPreferences?
    ) -> Bool {
        guard let binding = event.binding else { return false }
        guard
            let action = ShortcutAction.allCases.first(where: {
                if let preferences { return preferences.shortcut(for: $0) == binding }
                return $0.defaultBinding == binding
            })
        else {
            return false
        }

        switch action {
        case .toggleDenMode:
            if !event.isRepeat { store.toggleDenMode() }
        case .focusPreviousDesk:
            store.focusPreviousDesk()
        case .focusNextDesk:
            store.focusNextDesk()
        case .returnToPreviousDesk:
            store.returnToPreviousDesk()
        case .focusPreviousBoard:
            store.focusPreviousBoard()
        case .focusNextBoard:
            store.focusNextBoard()
        case .moveFocusedBoardLeft:
            store.moveFocusedBoardLeft()
        case .moveFocusedBoardRight:
            store.moveFocusedBoardRight()
        }
        return true
    }

    private static func handleDrawerDenModeToggle(
        _ event: KeyboardInput,
        store: DenStore,
        preferences: AppPreferences?
    ) -> Bool {
        guard let binding = event.binding else { return false }
        let toggleBinding =
            preferences?.shortcut(for: .toggleDenMode)
            ?? ShortcutAction.toggleDenMode.defaultBinding
        guard binding == toggleBinding else { return false }
        if !event.isRepeat {
            store.toggleDenMode()
        }
        return true
    }

    private static func handleDenMode(_ event: KeyboardInput, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if store.isDeskFilterPresented {
            return handleDeskFilter(event, store: store)
        }

        if isTab(event), modifiers == [], !event.isRepeat {
            store.toggleDrawer()
            return true
        }

        if isEscape(event), modifiers == [] {
            store.exitDenMode()
            return true
        }

        if characterIgnoringModifiers(for: event) == "/", modifiers == [] {
            store.enterDeskFilter()
            return true
        }

        if handleMovement(event, modifiers: modifiers, store: store, overview: false) {
            return true
        }

        if isQuestionMark(event, modifiers: modifiers) {
            store.showKeyboardShortcuts()
            return true
        }

        let baseCharacter = baseCharacter(for: event)
        if let digit = baseCharacter.flatMap(Int.init), (0...9).contains(digit) {
            let deskNumber = digit == 0 ? 10 : digit
            if modifiers == [] {
                store.focusDesk(number: deskNumber)
            } else if modifiers == [.shift] {
                store.moveFocusedBoard(toDeskNumber: deskNumber)
            }
            return true
        }

        if let stroke = KeyStroke(event: event), let command = denModeCommands[stroke.binding] {
            if command.repeatPolicy == .allow || !stroke.isRepeat {
                perform(command.action, store: store)
            }
        }

        return true
    }

    private static func handleDeskFilter(_ event: KeyboardInput, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)

        if store.isDeskFilterInputActive {
            if hasMarkedText(in: event) {
                return false
            }
            if isEscape(event), modifiers == [] {
                store.dismissDeskFilter()
                return true
            }
            if isReturn(event), modifiers == [] {
                store.confirmDeskFilterQuery()
                return true
            }
            return false
        }

        guard modifiers == [] else { return true }

        if isEscape(event) {
            store.dismissDeskFilter()
        } else if isReturn(event) {
            store.confirmDeskFilterSelection()
        } else if characterIgnoringModifiers(for: event) == "/" {
            store.enterDeskFilter()
        } else {
            switch event.key {
            case .leftArrow:
                store.selectDeskFilterBoard(by: -1)
            case .rightArrow:
                store.selectDeskFilterBoard(by: 1)
            default:
                switch characterIgnoringModifiers(for: event) {
                case "h": store.selectDeskFilterBoard(by: -1)
                case "l": store.selectDeskFilterBoard(by: 1)
                default: break
                }
            }
        }
        return true
    }

    private static let denModeCommands: [ShortcutBinding: KeyboardCommand] = [
        binding("n"): KeyboardCommand(action: .showOpenBoardPanel),
        binding(" "): KeyboardCommand(action: .showOpenBoardPanel),
        binding("n", modifiers: [.shift]): KeyboardCommand(action: .showNewDeskPanel),
        binding("p"): KeyboardCommand(action: .showSaveDeskPresetPanel, repeatPolicy: .ignore),
        binding("p", modifiers: [.shift]): KeyboardCommand(
            action: .showReplaceDeskPanel,
            repeatPolicy: .ignore),
        binding("o"): KeyboardCommand(action: .showOverview),
        binding("w"): KeyboardCommand(action: .showBoardWidthPanel, repeatPolicy: .ignore),
        binding("["): KeyboardCommand(action: .goBack),
        binding("]"): KeyboardCommand(action: .goForward),
        binding("[", modifiers: [.shift]): KeyboardCommand(action: .goToFirstSheet),
        binding("{", modifiers: [.shift]): KeyboardCommand(action: .goToFirstSheet),
        binding("]", modifiers: [.shift]): KeyboardCommand(action: .goToLatestSheet),
        binding("}", modifiers: [.shift]): KeyboardCommand(action: .goToLatestSheet),
        binding("-"): KeyboardCommand(action: .adjustBoardWidth(-80)),
        binding("="): KeyboardCommand(action: .adjustBoardWidth(80)),
        binding("=", modifiers: [.shift]): KeyboardCommand(action: .adjustBoardWidth(80)),
        binding("+", modifiers: [.shift]): KeyboardCommand(action: .adjustBoardWidth(80)),
        binding("f"): KeyboardCommand(action: .toggleBoardMaximized, repeatPolicy: .ignore),
        binding("c"): KeyboardCommand(action: .centerBoard, repeatPolicy: .ignore),
        binding("t"): KeyboardCommand(action: .toggleFocusedBoardSheetNavigationPause, repeatPolicy: .ignore),
        binding("s"): KeyboardCommand(action: .captureCurrentSheet, repeatPolicy: .ignore),
        binding("s", modifiers: [.shift]): KeyboardCommand(
            action: .captureFocusedDesk,
            repeatPolicy: .ignore),
        binding("a"): KeyboardCommand(action: .keepCurrentSheetInDrawer, repeatPolicy: .ignore),
        binding("z"): KeyboardCommand(action: .toggleZenView, repeatPolicy: .ignore),
        binding("x"): KeyboardCommand(action: .removeBoard, repeatPolicy: .ignore),
        binding("u"): KeyboardCommand(action: .restoreBoard, repeatPolicy: .ignore),
        binding("r"): KeyboardCommand(action: .showRenameBoardPanel, repeatPolicy: .ignore),
        binding("r", modifiers: [.shift]): KeyboardCommand(
            action: .showRenameDeskPanel,
            repeatPolicy: .ignore),
        binding("d"): KeyboardCommand(action: .removeBoard, repeatPolicy: .ignore),
        binding("d", modifiers: [.shift]): KeyboardCommand(action: .deleteDesk),
        binding("e"): KeyboardCommand(action: .showEditBoardLinkPanel, repeatPolicy: .ignore),
        ShortcutBinding(key: .returnKey, modifiers: [.shift]): KeyboardCommand(
            action: .duplicateFirstSheet,
            repeatPolicy: .ignore),
        ShortcutBinding(key: .returnKey, modifiers: []): KeyboardCommand(
            action: .duplicateBoard,
            repeatPolicy: .ignore),
    ]

    private static func binding(
        _ character: String,
        modifiers: ShortcutModifiers = []
    ) -> ShortcutBinding {
        ShortcutBinding(key: .character(character), modifiers: modifiers)
    }

    private static func perform(_ action: KeyboardAction, store: DenStore) {
        switch action {
        case .showOpenBoardPanel: store.showOpenBoardPanel()
        case .showNewDeskPanel: store.showNewDeskPanel()
        case .showSaveDeskPresetPanel: store.showSaveDeskPresetPanel()
        case .showReplaceDeskPanel: store.showReplaceDeskPanel()
        case .showOverview: store.showOverview()
        case .showBoardWidthPanel: store.showBoardWidthPanel()
        case .goBack: store.goBackInFocusedBoard()
        case .goForward: store.goForwardInFocusedBoard()
        case .goToFirstSheet: store.goToFirstSheetInFocusedBoard()
        case .goToLatestSheet: store.goToLatestSheetInFocusedBoard()
        case .adjustBoardWidth(let amount): store.adjustFocusedBoardWidth(by: amount)
        case .toggleBoardMaximized: store.toggleFocusedBoardMaximized()
        case .centerBoard: store.centerFocusedBoard()
        case .toggleFocusedBoardSheetNavigationPause: store.toggleFocusedBoardSheetNavigationPause()
        case .captureCurrentSheet: store.captureFocusedSheetScreenshot()
        case .captureFocusedDesk: store.captureFocusedDeskScreenshot()
        case .keepCurrentSheetInDrawer: store.keepFocusedSheetInDrawer()
        case .toggleZenView: store.toggleZenView()
        case .removeBoard: store.removeFocusedBoard()
        case .restoreBoard: store.restoreRecentlyRemovedBoard()
        case .showRenameBoardPanel: store.showRenameBoardPanel()
        case .showRenameDeskPanel: store.showRenameDeskPanel()
        case .deleteDesk: store.deleteFocusedDesk()
        case .showEditBoardLinkPanel: store.showEditBoardLinkPanel()
        case .duplicateBoard: store.duplicateFocusedBoard()
        case .duplicateFirstSheet: store.duplicateFocusedBoardFromFirstSheet()
        }
    }

    private static func handleDrawer(_ event: KeyboardInput, store: DenStore) -> Bool {
        if !store.isDenMode, event.isDrawerPreviewFirstResponder {
            return false
        }

        if store.isDrawerFilterInputActive {
            let modifiers = normalizedModifiers(for: event)
            if hasMarkedText(in: event) {
                return false
            }
            if isEscape(event), modifiers == [] {
                store.exitDrawerFilterMode()
                return true
            }
            if isReturn(event), modifiers == [] {
                store.confirmDrawerFilterQuery()
                return true
            }
            return false
        }

        if store.isDrawerFilterSelecting {
            let modifiers = normalizedModifiers(for: event)
            guard modifiers == [] else { return true }

            if isEscape(event) {
                store.exitDrawerFilterMode()
                return true
            }
            if isReturn(event) {
                store.confirmDrawerFilterSelection()
                return true
            }

            switch characterIgnoringModifiers(for: event) {
            case "j": store.selectDrawerItem(by: 1)
            case "k": store.selectDrawerItem(by: -1)
            default:
                switch event.key {
                case .downArrow: store.selectDrawerItem(by: 1)
                case .upArrow: store.selectDrawerItem(by: -1)
                default: break
                }
            }
            return true
        }

        if store.isDenMode {
            let modifiers = normalizedModifiers(for: event)
            if modifiers == [.shift], characterIgnoringModifiers(for: event) == "d" {
                if !event.isRepeat {
                    store.requestDrawerClearConfirmation()
                }
                return true
            }
            guard modifiers == [] else { return true }

            if isTab(event) {
                store.closeDrawer()
                return true
            }

            if isEscape(event) {
                store.exitDenMode()
                return true
            }

            if isReturn(event), !event.isRepeat {
                store.toggleSelectedDrawerItem()
                return true
            }

            if event.key == .backspace || event.key == .deleteForward {
                if !event.isRepeat {
                    store.discardSelectedDrawerItem()
                }
                return true
            }

            switch characterIgnoringModifiers(for: event) {
            case "/":
                store.enterDrawerFilterMode()
            case "j":
                store.selectDrawerItem(by: 1)
            case "k":
                store.selectDrawerItem(by: -1)
            case "p":
                if !event.isRepeat {
                    store.placeSelectedDrawerItemAsBoard()
                }
            case "x", "d":
                if !event.isRepeat {
                    store.discardSelectedDrawerItem()
                }
            default:
                switch event.key {
                case .downArrow: store.selectDrawerItem(by: 1)
                case .upArrow: store.selectDrawerItem(by: -1)
                default: break
                }
            }
            return true
        }

        let modifiers = normalizedModifiers(for: event)
        guard modifiers == [] else { return true }

        if isEscape(event) {
            store.closeDrawer()
            return true
        }

        if isReturn(event), !event.isRepeat {
            store.toggleSelectedDrawerItem()
            return true
        }

        if event.key == .backspace || event.key == .deleteForward {
            if !event.isRepeat {
                store.discardSelectedDrawerItem()
            }
            return true
        }

        switch event.key {
        case .downArrow: store.selectDrawerItem(by: 1)
        case .upArrow: store.selectDrawerItem(by: -1)
        default: return false
        }
        return true
    }

    private static func handleBoardWidthPanel(_ event: KeyboardInput, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if isEscape(event), modifiers == [] {
            store.hideBoardWidthPanel()
            return true
        }

        let character = characterIgnoringModifiers(for: event)
        if character == "w", modifiers == [], !event.isRepeat {
            store.hideBoardWidthPanel()
        } else if character == "-", modifiers == [] {
            store.adjustFocusedDeskBoardWidths(by: -80)
        } else if character == "=", modifiers == [] || modifiers == [.shift] {
            store.adjustFocusedDeskBoardWidths(by: 80)
        } else if let count = character.flatMap(Int.init), (1...9).contains(count), modifiers == [] {
            store.resizeFocusedDeskBoards(toFit: count)
        }
        return true
    }

    private static func handleOverview(_ event: KeyboardInput, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        let character = characterIgnoringModifiers(for: event)?.first

        if store.isOverviewFilterInputActive {
            if hasMarkedText(in: event) {
                return false
            }
            if isEscape(event), modifiers == [] {
                store.exitOverviewFilterMode()
                return true
            }
            if isReturn(event), modifiers == [] {
                store.confirmOverviewFilterQuery()
                return true
            }
            return false
        }
        if isEscape(event), modifiers == [] {
            if !store.overviewQuery.isEmpty {
                store.clearOverviewQuery()
            } else {
                store.hideOverview()
            }
            return true
        }
        if isReturn(event), modifiers == [] {
            store.enterOverviewSelection()
            return true
        }
        if character == "/", modifiers == [] {
            store.enterOverviewFilterMode()
            return true
        }
        if handleMovement(event, modifiers: modifiers, store: store, overview: true) {
            return true
        }
        return true
    }

    private static func hasMarkedText(in event: KeyboardInput) -> Bool {
        event.hasMarkedText
    }

    private static func handleMovement(
        _ event: KeyboardInput,
        modifiers: ShortcutModifiers,
        store: DenStore,
        overview: Bool
    ) -> Bool {
        guard modifiers == [] || modifiers == [.shift], let direction = movementDirection(for: event) else {
            return false
        }

        switch (overview, modifiers == [.shift], direction) {
        case (false, false, .left): store.focusPreviousBoard()
        case (false, false, .right): store.focusNextBoard()
        case (false, false, .upward): store.focusPreviousDesk()
        case (false, false, .down): store.focusNextDesk()
        case (false, true, .left): store.moveFocusedBoardLeft()
        case (false, true, .right): store.moveFocusedBoardRight()
        case (false, true, .upward): store.moveFocusedBoardToPreviousDesk()
        case (false, true, .down): store.moveFocusedBoardToNextDesk()
        case (true, false, .left): store.selectPreviousBoardInOverview()
        case (true, false, .right): store.selectNextBoardInOverview()
        case (true, false, .upward): store.selectPreviousDeskInOverview()
        case (true, false, .down): store.selectNextDeskInOverview()
        case (true, true, .left): store.moveOverviewSelectionBoardLeft()
        case (true, true, .right): store.moveOverviewSelectionBoardRight()
        case (true, true, .upward): store.moveOverviewSelectionBoardToPreviousDesk()
        case (true, true, .down): store.moveOverviewSelectionBoardToNextDesk()
        }
        return true
    }

    private static func movementDirection(for event: KeyboardInput) -> MovementDirection? {
        switch event.key {
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .upArrow: return .upward
        case .downArrow: return .down
        default:
            switch characterIgnoringModifiers(for: event) {
            case "h": return .left
            case "l": return .right
            case "k": return .upward
            case "j": return .down
            default: return nil
            }
        }
    }

    private static func normalizedModifiers(for event: KeyboardInput) -> ShortcutModifiers {
        event.modifiers
    }

    private static func characterIgnoringModifiers(for event: KeyboardInput) -> String? {
        event.character?.lowercased()
    }

    private static func baseCharacter(for event: KeyboardInput) -> String? {
        event.baseCharacter?.lowercased()
    }

    private static func isEscape(_ event: KeyboardInput) -> Bool {
        event.isEscape
    }

    private static func isQuestionMark(_ event: KeyboardInput, modifiers: ShortcutModifiers) -> Bool {
        modifiers == [.shift]
            && (event.characters == "?" || event.baseCharacter == "/")
    }

    private static func isReturn(_ event: KeyboardInput) -> Bool {
        event.key == .returnKey
    }

    private static func isTab(_ event: KeyboardInput) -> Bool {
        event.key == .tab
    }
}

private enum MovementDirection {
    case left
    case right
    case upward
    case down
}

private struct KeyStroke {
    let binding: ShortcutBinding
    let isRepeat: Bool

    init?(event: KeyboardInput) {
        let modifiers = event.modifiers
        if let character = event.character?.lowercased(),
            character.count == 1,
            character.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0)
            })
        {
            binding = ShortcutBinding(key: .character(character), modifiers: modifiers)
        } else {
            guard let binding = event.binding else { return nil }
            self.binding = binding
        }
        isRepeat = event.isRepeat
    }
}

private struct KeyboardCommand {
    let action: KeyboardAction
    let repeatPolicy: KeyRepeatPolicy

    init(action: KeyboardAction, repeatPolicy: KeyRepeatPolicy = .allow) {
        self.action = action
        self.repeatPolicy = repeatPolicy
    }
}

private enum KeyRepeatPolicy {
    case allow
    case ignore
}

private enum KeyboardAction {
    case showOpenBoardPanel
    case showNewDeskPanel
    case showSaveDeskPresetPanel
    case showReplaceDeskPanel
    case showOverview
    case showBoardWidthPanel
    case goBack
    case goForward
    case goToFirstSheet
    case goToLatestSheet
    case adjustBoardWidth(Double)
    case toggleBoardMaximized
    case centerBoard
    case toggleFocusedBoardSheetNavigationPause
    case captureCurrentSheet
    case captureFocusedDesk
    case keepCurrentSheetInDrawer
    case toggleZenView
    case removeBoard
    case restoreBoard
    case showRenameBoardPanel
    case showRenameDeskPanel
    case deleteDesk
    case showEditBoardLinkPanel
    case duplicateBoard
    case duplicateFirstSheet
}
