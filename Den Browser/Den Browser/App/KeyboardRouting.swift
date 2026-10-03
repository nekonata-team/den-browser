import Foundation

struct ShortcutConfiguration {
    let bindings: [ConfigurableShortcut: ShortcutBinding]
    let deskNumberBinding: ShortcutBinding?
    let essentials: [Essential]

    init(preferences: AppPreferences?) {
        essentials = preferences?.essentials ?? []
        if let preferences {
            bindings = Dictionary(
                uniqueKeysWithValues: ConfigurableShortcut.allCases.compactMap { shortcut in
                    preferences.shortcut(for: shortcut).map { (shortcut, $0) }
                })
            deskNumberBinding = preferences.deskNumberBinding
        } else {
            bindings = Dictionary(
                uniqueKeysWithValues: ConfigurableShortcut.allCases.map { ($0, $0.defaultBinding) })
            deskNumberBinding = AppPreferences.defaultDeskNumberBinding
        }
    }

    func shortcut(matching binding: ShortcutBinding) -> ConfigurableShortcut? {
        bindings.first(where: { $0.value == binding })?.key
    }

    func essential(matching key: String) -> Essential? {
        essentials.first { $0.key == key }
    }
}

enum InputDecision: Equatable {
    case perform(AppAction)
    case consume(InputReason)
    case forward(InputDestination)
}

enum InputReason: Equatable {
    case denModeUnmapped
    case exclusiveContext
    case dragging
    case ignoredRepeat
}

enum InputDestination: Equatable {
    case nativeCommand
    case temporaryTextInput
    case sheetOrTerminal
    case drawerPreview
    case filterTextInput
}

enum KeyboardRouter {
    static func route(
        event: KeyEvent,
        context: InputContext,
        shortcuts: ShortcutConfiguration
    ) -> InputDecision {
        if context.isFullscreenActive { return .forward(.sheetOrTerminal) }

        let modifiers = event.modifiers
        let character = event.character?.lowercased()

        if character == "q", modifiers == [.command] { return .forward(.nativeCommand) }
        if context.hasPendingConfirmation { return .forward(.temporaryTextInput) }

        if event.isEscape, modifiers == [.shift] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.overview(.toggleActivity))
        }

        if case .drawer? = context.surface,
            let binding = event.binding,
            binding == shortcuts.bindings[.toggleDenMode]
        {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.application(.toggleDenMode))
        }

        if case .notifications? = context.surface {
            return routeNotifications(event)
        }

        if case .board? = context.activeDrag {
            if event.isEscape, modifiers == [] { return .perform(.board(.requestDragCancellation)) }
            return .consume(.dragging)
        }
        if case .desk? = context.activeDrag {
            if event.isEscape, modifiers == [] { return .perform(.desk(.requestDragCancellation)) }
            return .consume(.dragging)
        }

        if character == "w", modifiers == [.command, .shift] { return .forward(.nativeCommand) }

        switch context.surface {
        case .notifications:
            return routeNotifications(event)
        case .deskFilter:
            break
        case .keyboardShortcuts:
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] {
                return .perform(.application(.hideKeyboardShortcuts))
            }
            return .forward(.filterTextInput)
        case .essentialsPrefix:
            return routeEssentialsPrefix(event, shortcuts: shortcuts)
        case .boardWidth:
            return routeBoardWidth(event)
        case .overview(let filterPhase, let hasQuery):
            return routeOverview(event, filterPhase: filterPhase, hasQuery: hasQuery, activeDrag: context.activeDrag)
        case .boardActivity:
            if event.isEscape, modifiers == [] { return .perform(.overview(.hideActivity)) }
            return .forward(.temporaryTextInput)
        case .drawer(let filterPhase, let previewFirstResponder):
            return routeDrawer(
                event,
                mode: context.mode,
                filterPhase: filterPhase,
                previewFirstResponder: previewFirstResponder)
        case .zmxSessions(let filterPhase, let hasQuery, let hasSelection):
            return routeZmxSessions(event, filterPhase: filterPhase, hasQuery: hasQuery, hasSelection: hasSelection)
        case .textInput:
            return .forward(.temporaryTextInput)
        case nil:
            break
        }

        if let character, ["l", "t", "w"].contains(character), modifiers == [.command] {
            return .forward(.nativeCommand)
        }

        if context.hasFocusedBoard {
            if character == "=", modifiers == [.command] || modifiers == [.command, .shift] {
                return .perform(.board(.increaseContentSize))
            }
            if character == "-", modifiers == [.command] {
                return .perform(.board(.decreaseContentSize))
            }
            if character == "0", modifiers == [.command] {
                return .perform(.board(.resetContentSize))
            }
        }

        if context.mode == .sheet,
            let deskNumberBinding = shortcuts.deskNumberBinding,
            modifiers == deskNumberBinding.modifiers,
            let digit = event.baseCharacter.flatMap({ Int($0.lowercased()) }),
            (0...9).contains(digit)
        {
            return .perform(.desk(.focus(digit == 0 ? 10 : digit)))
        }

        if context.mode == .sheet, character == "r", modifiers == [.command] {
            return .forward(.nativeCommand)
        }
        if character == "r", modifiers == [.command, .shift] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.board(.reloadFromOrigin))
        }
        if character == "r", modifiers == [.command, .option, .shift] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.desk(.reloadSheets))
        }

        if context.mode == .den, case .deskFilter(let phase)? = context.surface {
            return routeDeskFilter(event, phase: phase)
        }

        if context.mode == .den, character == ",", modifiers == [] {
            return .perform(.application(.openSettings))
        }

        if context.mode == .den, character == "g", modifiers == [] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.essentials(.enterPrefix))
        }

        if let binding = event.binding, let shortcut = shortcuts.shortcut(matching: binding) {
            return route(shortcut: shortcut, isRepeat: event.isRepeat)
        }

        if context.mode == .den { return routeDenMode(event) }
        return .forward(.sheetOrTerminal)
    }

    private static func routeNotifications(_ event: KeyEvent) -> InputDecision {
        if event.isEscape, event.modifiers == [] { return .perform(.notifications(.close)) }
        if event.modifiers == [] {
            if event.key == .upArrow { return .perform(.notifications(.moveSelection(-1))) }
            if event.key == .downArrow { return .perform(.notifications(.moveSelection(1))) }
            if event.key == .returnKey { return .perform(.notifications(.openSelected)) }
        }
        return .consume(.exclusiveContext)
    }

    private static func route(shortcut: ConfigurableShortcut, isRepeat: Bool) -> InputDecision {
        if [.toggleDenMode, .toggleBoardRail].contains(shortcut), isRepeat {
            return .consume(.ignoredRepeat)
        }
        let action: AppAction =
            switch shortcut {
            case .toggleDenMode: .application(.toggleDenMode)
            case .toggleBoardRail: .application(.toggleBoardRail)
            case .focusPreviousDesk: .desk(.focusPrevious)
            case .focusNextDesk: .desk(.focusNext)
            case .returnToPreviousDesk: .desk(.returnToPrevious)
            case .focusPreviousBoard: .board(.focusPrevious)
            case .focusNextBoard: .board(.focusNext)
            case .moveFocusedBoardLeft: .board(.moveLeft)
            case .moveFocusedBoardRight: .board(.moveRight)
            }
        return .perform(action)
    }

    private static func routeEssentialsPrefix(
        _ event: KeyEvent,
        shortcuts: ShortcutConfiguration
    ) -> InputDecision {
        if event.modifiers == [] {
            if event.key == .upArrow { return .perform(.essentials(.moveSelection(-1))) }
            if event.key == .downArrow { return .perform(.essentials(.moveSelection(1))) }
        }
        if event.isRepeat { return .consume(.ignoredRepeat) }
        if event.isEscape, event.modifiers == [] {
            return .perform(.essentials(.exitPrefix))
        }
        if event.modifiers == [] {
            if event.key == .returnKey { return .perform(.essentials(.launchSelected)) }
        }
        guard
            event.modifiers == [] || event.modifiers == [.shift],
            let character = event.characters,
            !character.isEmpty
        else {
            return .perform(.essentials(.exitPrefix))
        }
        guard let essential = shortcuts.essential(matching: character) else {
            return .perform(.essentials(.showNotFound(character)))
        }
        return .perform(.essentials(.launch(essential.id)))
    }

    private static func routeDenMode(_ event: KeyEvent) -> InputDecision {
        let modifiers = event.modifiers
        let character = event.character?.lowercased()

        if event.key == .tab, modifiers == [] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.drawer(.toggle))
        }
        if event.isEscape, modifiers == [] { return .perform(.application(.exitDenMode)) }
        if modifiers == [.shift] {
            switch event.characters {
            case "<": return .perform(.board(.revealPrevious))
            case ">": return .perform(.board(.revealNext))
            default: break
            }
        }
        if character == "/", modifiers == [] { return .perform(.desk(.enterFilter)) }
        if let action = movementAction(event, overview: false) { return .perform(action) }
        if isQuestionMark(event) { return .perform(.application(.showKeyboardShortcuts)) }

        if let digit = event.baseCharacter.flatMap({ Int($0.lowercased()) }), (0...9).contains(digit) {
            let deskNumber = digit == 0 ? 10 : digit
            if modifiers == [] { return .perform(.desk(.focus(deskNumber))) }
            if modifiers == [.shift] { return .perform(.board(.moveToDesk(deskNumber))) }
            return .consume(.denModeUnmapped)
        }

        guard let stroke = KeyStroke(event: event), let command = denModeCommands[stroke.binding] else {
            return .consume(.denModeUnmapped)
        }
        if command.repeatPolicy == .ignore, stroke.isRepeat { return .consume(.ignoredRepeat) }
        return .perform(command.action)
    }

    private static func routeDeskFilter(_ event: KeyEvent, phase: DenFilterPhase) -> InputDecision {
        let modifiers = event.modifiers
        if phase == .filtering {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] { return .perform(.desk(.dismissFilter)) }
            if event.key == .returnKey, modifiers == [] { return .perform(.desk(.confirmFilterQuery)) }
            return .forward(.filterTextInput)
        }
        guard modifiers == [] else { return .consume(.exclusiveContext) }
        if event.isEscape { return .perform(.desk(.dismissFilter)) }
        if event.key == .returnKey { return .perform(.desk(.confirmFilterSelection)) }
        if event.character?.lowercased() == "/" { return .perform(.desk(.enterFilter)) }
        return switch (event.key, event.character?.lowercased()) {
        case (.leftArrow, _), (_, "h"): .perform(.desk(.selectFilterBoard(-1)))
        case (.rightArrow, _), (_, "l"): .perform(.desk(.selectFilterBoard(1)))
        default: .consume(.exclusiveContext)
        }
    }

    private static func routeDrawer(
        _ event: KeyEvent,
        mode: KeyboardMode,
        filterPhase: DenFilterPhase,
        previewFirstResponder: Bool
    ) -> InputDecision {
        let modifiers = event.modifiers
        let character = event.character?.lowercased()

        if modifiers == [.command], character == "w" {
            return event.isRepeat
                ? .consume(.ignoredRepeat)
                : .perform(.drawer(.discardSelectedItem(focusNext: true)))
        }
        if event.isEscape, modifiers == [.control] { return .perform(.drawer(.close)) }
        if mode == .sheet, previewFirstResponder { return .forward(.drawerPreview) }

        if filterPhase == .filtering {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] { return .perform(.drawer(.exitFilterMode)) }
            if event.key == .returnKey, modifiers == [] { return .perform(.drawer(.confirmFilterQuery)) }
            return .forward(.filterTextInput)
        }
        if filterPhase == .selecting {
            guard modifiers == [] else { return .consume(.exclusiveContext) }
            if event.isEscape { return .perform(.drawer(.exitFilterMode)) }
            if event.key == .returnKey { return .perform(.drawer(.confirmFilterSelection)) }
            return switch (event.key, event.character?.lowercased()) {
            case (.downArrow, _), (_, "j"): .perform(.drawer(.selectItem(1)))
            case (.upArrow, _), (_, "k"): .perform(.drawer(.selectItem(-1)))
            default: .consume(.exclusiveContext)
            }
        }

        if mode == .den {
            if modifiers == [], event.character?.lowercased() == "u" {
                return event.isRepeat
                    ? .consume(.ignoredRepeat)
                    : .perform(.drawer(.restoreDiscardedItem))
            }
            if modifiers == [.shift], event.character?.lowercased() == "d" {
                return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.drawer(.requestClearConfirmation))
            }
            guard modifiers == [] else { return .consume(.exclusiveContext) }
            if event.key == .tab { return .perform(.drawer(.close)) }
            if event.isEscape { return .perform(.application(.exitDenMode)) }
            if event.key == .returnKey {
                return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.drawer(.toggleSelectedItem))
            }
            if event.key == .backspace || event.key == .deleteForward {
                return event.isRepeat
                    ? .consume(.ignoredRepeat)
                    : .perform(.drawer(.discardSelectedItem(focusNext: true)))
            }
            let action: AppAction? =
                switch event.character?.lowercased() {
                case "/": .drawer(.enterFilterMode)
                case "f": .drawer(.toggleStyle)
                case "j": .drawer(.selectItem(1))
                case "k": .drawer(.selectItem(-1))
                case "p": .drawer(.placeSelectedItemAsBoard)
                case "x": .drawer(.discardSelectedItem(focusNext: false))
                case "d": .drawer(.discardSelectedItem(focusNext: true))
                default:
                    switch event.key {
                    case .downArrow: .drawer(.selectItem(1))
                    case .upArrow: .drawer(.selectItem(-1))
                    default: nil
                    }
                }
            guard let action else { return .consume(.exclusiveContext) }
            if event.isRepeat {
                switch action {
                case .drawer(.placeSelectedItemAsBoard), .drawer(.discardSelectedItem),
                    .drawer(.toggleStyle):
                    return .consume(.ignoredRepeat)
                default:
                    break
                }
            }
            return .perform(action)
        }

        guard modifiers == [] else { return .consume(.exclusiveContext) }
        if event.isEscape { return .perform(.drawer(.close)) }
        if event.key == .returnKey {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.drawer(.toggleSelectedItem))
        }
        if event.key == .backspace || event.key == .deleteForward {
            return event.isRepeat
                ? .consume(.ignoredRepeat)
                : .perform(.drawer(.discardSelectedItem(focusNext: true)))
        }
        return switch event.key {
        case .downArrow: .perform(.drawer(.selectItem(1)))
        case .upArrow: .perform(.drawer(.selectItem(-1)))
        default: .consume(.exclusiveContext)
        }
    }

    private static func routeBoardWidth(_ event: KeyEvent) -> InputDecision {
        let modifiers = event.modifiers
        let character = event.character?.lowercased()
        if event.isEscape, modifiers == [] { return .perform(.board(.hideWidthPanel)) }
        if character == "w", modifiers == [] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.board(.hideWidthPanel))
        }
        if character == "-", modifiers == [] { return .perform(.desk(.adjustBoardWidths(-80))) }
        if character == "=", modifiers == [] || modifiers == [.shift] {
            return .perform(.desk(.adjustBoardWidths(80)))
        }
        if let count = character.flatMap(Int.init), (1...9).contains(count), modifiers == [] {
            return .perform(.desk(.resizeBoards(count)))
        }
        return .consume(.exclusiveContext)
    }

    private static func routeOverview(
        _ event: KeyEvent,
        filterPhase: DenFilterPhase,
        hasQuery: Bool,
        activeDrag: ActiveDrag?
    ) -> InputDecision {
        let modifiers = event.modifiers
        if filterPhase == .filtering {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] { return .perform(.overview(.exitFilterMode)) }
            if event.key == .returnKey, modifiers == [] { return .perform(.overview(.confirmFilterQuery)) }
            return .forward(.filterTextInput)
        }
        if case .board? = activeDrag, event.isEscape, modifiers == [] {
            return .perform(.board(.requestDragCancellation))
        }
        if event.isEscape, modifiers == [] {
            return .perform(hasQuery ? .overview(.clearQuery) : .overview(.hide))
        }
        if event.key == .returnKey, modifiers == [] { return .perform(.overview(.enterSelection)) }
        if event.character?.lowercased() == "/", modifiers == [] {
            return .perform(.overview(.enterFilterMode))
        }
        if let action = movementAction(event, overview: true) { return .perform(action) }
        return .consume(.exclusiveContext)
    }

    private static func routeZmxSessions(
        _ event: KeyEvent,
        filterPhase: DenFilterPhase,
        hasQuery: Bool,
        hasSelection: Bool
    ) -> InputDecision {
        let modifiers = event.modifiers
        if filterPhase == .filtering {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if modifiers == [.command], event.character?.lowercased() == "a" {
                return .perform(.zmxSessions(.selectAll))
            }
            if event.isEscape, modifiers == [] { return .perform(.zmxSessions(.exitFilter)) }
            if event.key == .upArrow, modifiers == [] {
                return .perform(.zmxSessions(.moveSelection(-1)))
            }
            if event.key == .downArrow, modifiers == [] {
                return .perform(.zmxSessions(.moveSelection(1)))
            }
            if event.key == .returnKey, modifiers == [] { return .perform(.zmxSessions(.openSelected)) }
            return .forward(.filterTextInput)
        }
        if event.isEscape {
            guard modifiers == [] else { return .consume(.exclusiveContext) }
            if hasSelection { return .perform(.zmxSessions(.clearSelection)) }
            return .perform(hasQuery ? .zmxSessions(.clearFilter) : .zmxSessions(.hide))
        }
        if modifiers == [.command], event.character?.lowercased() == "a" {
            return .perform(.zmxSessions(.selectAll))
        }
        guard modifiers == [] else { return .consume(.exclusiveContext) }
        if event.character?.lowercased() == "/" { return .perform(.zmxSessions(.enterFilter)) }
        if event.key == .upArrow { return .perform(.zmxSessions(.moveSelection(-1))) }
        if event.key == .downArrow { return .perform(.zmxSessions(.moveSelection(1))) }
        if event.character?.lowercased() == "k" { return .perform(.zmxSessions(.moveSelection(-1))) }
        if event.character?.lowercased() == "j" { return .perform(.zmxSessions(.moveSelection(1))) }
        if event.character == " " { return .perform(.zmxSessions(.toggleSelection)) }
        if event.key == .returnKey { return .perform(.zmxSessions(.openSelected)) }
        if event.key == .backspace || event.key == .deleteForward {
            return .perform(.zmxSessions(.deleteSelected))
        }
        if event.character?.lowercased() == "x" { return .perform(.zmxSessions(.deleteSelected)) }
        if event.character?.lowercased() == "r" { return .perform(.zmxSessions(.refresh)) }
        return .consume(.exclusiveContext)
    }

    private static func movementAction(_ event: KeyEvent, overview: Bool) -> AppAction? {
        guard event.modifiers == [] || event.modifiers == [.shift], let direction = direction(for: event) else {
            return nil
        }
        return switch (overview, event.modifiers == [.shift], direction) {
        case (false, false, .left): .board(.focusPrevious)
        case (false, false, .right): .board(.focusNext)
        case (false, false, .upward): .desk(.focusPrevious)
        case (false, false, .down): .desk(.focusNext)
        case (false, true, .left): .board(.moveLeft)
        case (false, true, .right): .board(.moveRight)
        case (false, true, .upward): .board(.moveToPreviousDesk)
        case (false, true, .down): .board(.moveToNextDesk)
        case (true, false, .left): .overview(.selectPreviousBoard)
        case (true, false, .right): .overview(.selectNextBoard)
        case (true, false, .upward): .overview(.selectPreviousDesk)
        case (true, false, .down): .overview(.selectNextDesk)
        case (true, true, .left): .overview(.moveSelectionBoardLeft)
        case (true, true, .right): .overview(.moveSelectionBoardRight)
        case (true, true, .upward): .overview(.moveSelectionBoardToPreviousDesk)
        case (true, true, .down): .overview(.moveSelectionBoardToNextDesk)
        }
    }

    private static func direction(for event: KeyEvent) -> MovementDirection? {
        switch event.key {
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .upArrow: return .upward
        case .downArrow: return .down
        default:
            return switch event.character?.lowercased() {
            case "h": .left
            case "l": .right
            case "k": .upward
            case "j": .down
            default: nil
            }
        }
    }

    private static func isQuestionMark(_ event: KeyEvent) -> Bool {
        event.modifiers == [.shift] && (event.characters == "?" || event.baseCharacter == "/")
    }

    private static let denModeCommands: [ShortcutBinding: KeyboardCommand] = [
        binding("i"): KeyboardCommand(action: .notifications(.toggle)),
        binding("n"): KeyboardCommand(action: .board(.showOpenPanel)),
        binding(" "): KeyboardCommand(action: .board(.showOpenPanel)),
        binding("v"): KeyboardCommand(action: .board(.openFromClipboard), repeatPolicy: .ignore),
        binding("n", modifiers: [.shift]): KeyboardCommand(action: .desk(.showNewPanel)),
        binding("p"): KeyboardCommand(action: .desk(.showSavePresetPanel), repeatPolicy: .ignore),
        binding("p", modifiers: [.shift]): KeyboardCommand(action: .desk(.showReplacePanel), repeatPolicy: .ignore),
        binding("p", modifiers: [.control]): KeyboardCommand(action: .desk(.showPresetManager), repeatPolicy: .ignore),
        binding("o"): KeyboardCommand(action: .overview(.show)),
        binding("w"): KeyboardCommand(action: .board(.showWidthPanel), repeatPolicy: .ignore),
        binding("["): KeyboardCommand(action: .board(.goBack)),
        binding("]"): KeyboardCommand(action: .board(.goForward)),
        binding("[", modifiers: [.shift]): KeyboardCommand(action: .board(.goToFirstSheet)),
        binding("{", modifiers: [.shift]): KeyboardCommand(action: .board(.goToFirstSheet)),
        binding("]", modifiers: [.shift]): KeyboardCommand(action: .board(.goToLatestSheet)),
        binding("}", modifiers: [.shift]): KeyboardCommand(action: .board(.goToLatestSheet)),
        binding("-"): KeyboardCommand(action: .board(.adjustWidth(-80))),
        binding("="): KeyboardCommand(action: .board(.adjustWidth(80))),
        binding("=", modifiers: [.shift]): KeyboardCommand(action: .board(.adjustWidth(80))),
        binding("+", modifiers: [.shift]): KeyboardCommand(action: .board(.adjustWidth(80))),
        binding("f"): KeyboardCommand(action: .board(.toggleMaximized), repeatPolicy: .ignore),
        binding("f", modifiers: [.shift]): KeyboardCommand(
            action: .application(.toggleFocusMode), repeatPolicy: .ignore),
        binding("c"): KeyboardCommand(action: .board(.center), repeatPolicy: .ignore),
        binding("t"): KeyboardCommand(action: .board(.toggleSheetNavigationPause), repeatPolicy: .ignore),
        binding("s"): KeyboardCommand(action: .board(.captureSheet), repeatPolicy: .ignore),
        binding("s", modifiers: [.control]): KeyboardCommand(
            action: .board(.copySheetScreenshot), repeatPolicy: .ignore),
        binding("y"): KeyboardCommand(action: .board(.copyLocation), repeatPolicy: .ignore),
        binding("y", modifiers: [.shift]): KeyboardCommand(action: .board(.copyID), repeatPolicy: .ignore),
        binding("a"): KeyboardCommand(action: .board(.keepSheetInDrawer), repeatPolicy: .ignore),
        binding("z"): KeyboardCommand(action: .application(.toggleZenView), repeatPolicy: .ignore),
        binding("x"): KeyboardCommand(action: .board(.remove), repeatPolicy: .ignore),
        binding("u"): KeyboardCommand(action: .board(.restore), repeatPolicy: .ignore),
        binding("r"): KeyboardCommand(action: .board(.showRenamePanel), repeatPolicy: .ignore),
        binding("r", modifiers: [.shift]): KeyboardCommand(action: .desk(.showRenamePanel), repeatPolicy: .ignore),
        binding("d"): KeyboardCommand(action: .board(.removeAndFocusNext), repeatPolicy: .ignore),
        binding("d", modifiers: [.shift]): KeyboardCommand(action: .desk(.delete)),
        binding("m"): KeyboardCommand(action: .board(.toggleAnchor), repeatPolicy: .ignore),
        binding("m", modifiers: [.shift]): KeyboardCommand(action: .board(.jumpToAnchor), repeatPolicy: .ignore),
        binding("b"): KeyboardCommand(action: .essentials(.saveFocusedBoardAsEssential), repeatPolicy: .ignore),
        binding("e"): KeyboardCommand(action: .board(.showEditLinkPanel), repeatPolicy: .ignore),
        ShortcutBinding(key: .returnKey, modifiers: [.shift]): KeyboardCommand(
            action: .board(.duplicateFirstSheet), repeatPolicy: .ignore),
        ShortcutBinding(key: .returnKey, modifiers: []): KeyboardCommand(
            action: .board(.duplicate), repeatPolicy: .ignore),
    ]

    private static func binding(
        _ character: String,
        modifiers: ShortcutModifiers = []
    ) -> ShortcutBinding {
        ShortcutBinding(key: .character(character), modifiers: modifiers)
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

    init?(event: KeyEvent) {
        if let character = event.character?.lowercased(),
            character.count == 1,
            character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        {
            binding = ShortcutBinding(key: .character(character), modifiers: event.modifiers)
        } else {
            guard let binding = event.binding else { return nil }
            self.binding = binding
        }
        isRepeat = event.isRepeat
    }
}

private struct KeyboardCommand {
    let action: AppAction
    let repeatPolicy: KeyRepeatPolicy

    init(action: AppAction, repeatPolicy: KeyRepeatPolicy = .allow) {
        self.action = action
        self.repeatPolicy = repeatPolicy
    }
}

private enum KeyRepeatPolicy {
    case allow
    case ignore
}
