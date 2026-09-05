import AppKit
import Foundation

struct KeyEvent {
    let character: String?
    let baseCharacter: String?
    let characters: String?
    let key: ShortcutKey?
    let modifiers: ShortcutModifiers
    let isRepeat: Bool
    let hasMarkedText: Bool
    let isEscape: Bool

    var binding: ShortcutBinding? {
        guard let key else { return nil }
        return ShortcutBinding(key: key, modifiers: modifiers)
    }

    init(_ event: NSEvent) {
        character = event.charactersIgnoringModifiers
        baseCharacter = event.characters(byApplyingModifiers: [])
        characters = event.characters
        key = ShortcutKey(event: event)
        modifiers = ShortcutModifiers(event.modifierFlags)
        isRepeat = event.isARepeat
        hasMarkedText = TextInputComposition.isActive(in: event.window)
        isEscape = event.keyCode == 53
    }
}

struct InputContext {
    let isFullscreenActive: Bool
    let hasPendingConfirmation: Bool
    let isDrawerOpen: Bool
    let isBoardDragging: Bool
    let isDeskDragging: Bool
    let temporaryContext: TemporaryContext?
    let isDenMode: Bool
    let isDeskFilterPresented: Bool
    let isDeskFilterInputActive: Bool
    let isDrawerPreviewFirstResponder: Bool
    let isDrawerFilterInputActive: Bool
    let isDrawerFilterSelecting: Bool
    let isOverviewFilterInputActive: Bool
    let hasOverviewQuery: Bool
    let isZmxSessionFilterInputActive: Bool
    let hasZmxSessionQuery: Bool
    let isNotificationListPresented: Bool

    init(store: DenStore, event: NSEvent) {
        isFullscreenActive = store.isFullscreenActive
        hasPendingConfirmation = store.hasPendingConfirmation
        isDrawerOpen = store.isDrawerOpen
        isBoardDragging = store.isBoardDragging
        isDeskDragging = store.isDeskDragging
        temporaryContext = store.temporaryContext
        isDenMode = store.isDenMode
        isDeskFilterPresented = store.isDeskFilterPresented
        isDeskFilterInputActive = store.isDeskFilterInputActive
        isDrawerPreviewFirstResponder = Self.isDrawerPreviewFirstResponder(event, store: store)
        isDrawerFilterInputActive = store.isDrawerFilterInputActive
        isDrawerFilterSelecting = store.isDrawerFilterSelecting
        isOverviewFilterInputActive = store.isOverviewFilterInputActive
        hasOverviewQuery = !store.overviewQuery.isEmpty
        isZmxSessionFilterInputActive = store.zmxSessions.isFilterInputActive
        hasZmxSessionQuery = !store.zmxSessions.query.isEmpty
        isNotificationListPresented = store.isNotificationListPresented
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

enum AppAction: Equatable {
    case openSettings
    case toggleNotifications
    case closeNotifications
    case moveNotificationSelection(Int)
    case openSelectedNotification
    case toggleDenMode
    case exitDenMode
    case enterEssentialsPrefix
    case exitEssentialsPrefix
    case showEssentialNotFound(String)
    case launchEssential(UUID)
    case focusPreviousDesk
    case focusNextDesk
    case returnToPreviousDesk
    case focusPreviousBoard
    case focusNextBoard
    case moveFocusedBoardLeft
    case moveFocusedBoardRight
    case moveFocusedBoardToPreviousDesk
    case moveFocusedBoardToNextDesk
    case focusDesk(Int)
    case moveFocusedBoardToDesk(Int)
    case showOpenBoardPanel
    case openBoardFromClipboard
    case hideZmxSessions
    case enterZmxSessionFilter
    case exitZmxSessionFilter
    case confirmZmxSessionFilterQuery
    case clearZmxSessionFilter
    case moveZmxSessionSelection(Int)
    case openSelectedZmxSession
    case deleteSelectedZmxSession
    case refreshZmxSessions
    case showNewDeskPanel
    case showSaveDeskPresetPanel
    case showReplaceDeskPanel
    case showOverview
    case hideOverview
    case toggleBoardActivity
    case hideBoardActivity
    case enterOverviewSelection
    case enterOverviewFilterMode
    case exitOverviewFilterMode
    case confirmOverviewFilterQuery
    case clearOverviewQuery
    case selectPreviousBoardInOverview
    case selectNextBoardInOverview
    case selectPreviousDeskInOverview
    case selectNextDeskInOverview
    case moveOverviewSelectionBoardLeft
    case moveOverviewSelectionBoardRight
    case moveOverviewSelectionBoardToPreviousDesk
    case moveOverviewSelectionBoardToNextDesk
    case showKeyboardShortcuts
    case hideKeyboardShortcuts
    case showBoardWidthPanel
    case hideBoardWidthPanel
    case adjustFocusedDeskBoardWidths(Double)
    case resizeFocusedDeskBoards(Int)
    case toggleDrawer
    case closeDrawer
    case enterDrawerFilterMode
    case exitDrawerFilterMode
    case confirmDrawerFilterQuery
    case confirmDrawerFilterSelection
    case selectDrawerItem(Int)
    case toggleSelectedDrawerItem
    case discardSelectedDrawerItem(focusNext: Bool)
    case restoreDiscardedDrawerItem
    case placeSelectedDrawerItemAsBoard
    case requestDrawerClearConfirmation
    case enterDeskFilter
    case dismissDeskFilter
    case confirmDeskFilterQuery
    case confirmDeskFilterSelection
    case selectDeskFilterBoard(Int)
    case requestBoardDragCancellation
    case requestDeskDragCancellation
    case reloadFocusedBoardFromOrigin
    case reloadFocusedDeskSheets
    case reloadFocusedBoard
    case goBack
    case goForward
    case goToFirstSheet
    case goToLatestSheet
    case adjustBoardWidth(Double)
    case toggleBoardMaximized
    case centerBoard
    case revealPreviousBoard
    case revealNextBoard
    case toggleFocusedBoardSheetNavigationPause
    case captureCurrentSheet
    case captureFocusedDesk
    case copyCurrentSheetScreenshot
    case copyFocusedDeskScreenshot
    case keepCurrentSheetInDrawer
    case toggleZenView
    case toggleFocusMode
    case removeBoard
    case removeBoardAndFocusNext
    case restoreBoard
    case showRenameBoardPanel
    case showRenameDeskPanel
    case saveFocusedBoardAsEssential
    case deleteDesk
    case showEditBoardLinkPanel
    case duplicateBoard
    case duplicateFirstSheet
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
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.toggleBoardActivity)
        }

        if context.isDrawerOpen,
            let binding = event.binding,
            binding == shortcuts.bindings[.toggleDenMode]
        {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.toggleDenMode)
        }

        if context.isNotificationListPresented {
            if event.isEscape, modifiers == [] { return .perform(.closeNotifications) }
            if modifiers == [] {
                if event.key == .upArrow { return .perform(.moveNotificationSelection(-1)) }
                if event.key == .downArrow { return .perform(.moveNotificationSelection(1)) }
                if event.key == .returnKey { return .perform(.openSelectedNotification) }
            }
            return .consume(.exclusiveContext)
        }

        if context.isBoardDragging {
            if event.isEscape, modifiers == [] { return .perform(.requestBoardDragCancellation) }
            return .consume(.dragging)
        }
        if context.isDeskDragging {
            if event.isEscape, modifiers == [] { return .perform(.requestDeskDragCancellation) }
            return .consume(.dragging)
        }

        if character == "w", modifiers == [.command, .shift] { return .forward(.nativeCommand) }

        switch context.temporaryContext {
        case .keyboardShortcuts:
            if (event.isEscape && modifiers == []) || isQuestionMark(event) {
                return .perform(.hideKeyboardShortcuts)
            }
            return .consume(.exclusiveContext)
        case .essentialsPrefix:
            return routeEssentialsPrefix(event, shortcuts: shortcuts)
        case .boardWidth:
            return routeBoardWidth(event)
        case .overview:
            return routeOverview(event, context: context)
        case .boardActivity:
            if event.isEscape, modifiers == [] { return .perform(.hideBoardActivity) }
            return .forward(.temporaryTextInput)
        case .drawer:
            return routeDrawer(event, context: context)
        case .zmxSessions:
            return routeZmxSessions(event, context: context)
        case .openBoard, .zmxDuplication, .editBoardLink, .newDesk, .replaceDesk, .deskPresetManagement,
            .saveDeskPreset, .renameBoard, .renameDesk, .saveEssential:
            return .forward(.temporaryTextInput)
        case nil:
            break
        }

        if let character, ["l", "t", "w"].contains(character), modifiers == [.command] {
            return .forward(.nativeCommand)
        }

        if !context.isDenMode,
            let deskNumberBinding = shortcuts.deskNumberBinding,
            modifiers == deskNumberBinding.modifiers,
            let digit = event.baseCharacter.flatMap({ Int($0.lowercased()) }),
            (0...9).contains(digit)
        {
            return .perform(.focusDesk(digit == 0 ? 10 : digit))
        }

        if !context.isDenMode, character == "r", modifiers == [.command] {
            return .forward(.nativeCommand)
        }
        if character == "r", modifiers == [.command, .shift] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.reloadFocusedBoardFromOrigin)
        }
        if character == "r", modifiers == [.command, .option, .shift] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.reloadFocusedDeskSheets)
        }

        if context.isDenMode, context.isDeskFilterPresented {
            return routeDeskFilter(event, context: context)
        }

        if context.isDenMode, character == ",", modifiers == [] {
            return .perform(.openSettings)
        }

        if context.isDenMode, character == "g", modifiers == [] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.enterEssentialsPrefix)
        }

        if let binding = event.binding, let shortcut = shortcuts.shortcut(matching: binding) {
            return route(shortcut: shortcut, isRepeat: event.isRepeat)
        }

        if context.isDenMode { return routeDenMode(event) }
        return .forward(.sheetOrTerminal)
    }

    private static func route(shortcut: ConfigurableShortcut, isRepeat: Bool) -> InputDecision {
        if shortcut == .toggleDenMode, isRepeat { return .consume(.ignoredRepeat) }
        let action: AppAction =
            switch shortcut {
            case .toggleDenMode: .toggleDenMode
            case .focusPreviousDesk: .focusPreviousDesk
            case .focusNextDesk: .focusNextDesk
            case .returnToPreviousDesk: .returnToPreviousDesk
            case .focusPreviousBoard: .focusPreviousBoard
            case .focusNextBoard: .focusNextBoard
            case .moveFocusedBoardLeft: .moveFocusedBoardLeft
            case .moveFocusedBoardRight: .moveFocusedBoardRight
            }
        return .perform(action)
    }

    private static func routeEssentialsPrefix(
        _ event: KeyEvent,
        shortcuts: ShortcutConfiguration
    ) -> InputDecision {
        if event.isRepeat { return .consume(.ignoredRepeat) }
        if event.isEscape, event.modifiers == [] {
            return .perform(.exitEssentialsPrefix)
        }
        guard
            event.modifiers == [] || event.modifiers == [.shift],
            let character = event.characters,
            !character.isEmpty
        else {
            return .perform(.exitEssentialsPrefix)
        }
        guard let essential = shortcuts.essential(matching: character) else {
            return .perform(.showEssentialNotFound(character))
        }
        return .perform(.launchEssential(essential.id))
    }

    private static func routeDenMode(_ event: KeyEvent) -> InputDecision {
        let modifiers = event.modifiers
        let character = event.character?.lowercased()

        if event.key == .tab, modifiers == [] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.toggleDrawer)
        }
        if event.isEscape, modifiers == [] { return .perform(.exitDenMode) }
        if modifiers == [.shift] {
            switch event.characters {
            case "<": return .perform(.revealPreviousBoard)
            case ">": return .perform(.revealNextBoard)
            default: break
            }
        }
        if character == "/", modifiers == [] { return .perform(.enterDeskFilter) }
        if let action = movementAction(event, overview: false) { return .perform(action) }
        if isQuestionMark(event) { return .perform(.showKeyboardShortcuts) }

        if let digit = event.baseCharacter.flatMap({ Int($0.lowercased()) }), (0...9).contains(digit) {
            let deskNumber = digit == 0 ? 10 : digit
            if modifiers == [] { return .perform(.focusDesk(deskNumber)) }
            if modifiers == [.shift] { return .perform(.moveFocusedBoardToDesk(deskNumber)) }
            return .consume(.denModeUnmapped)
        }

        guard let stroke = KeyStroke(event: event), let command = denModeCommands[stroke.binding] else {
            return .consume(.denModeUnmapped)
        }
        if command.repeatPolicy == .ignore, stroke.isRepeat { return .consume(.ignoredRepeat) }
        return .perform(command.action)
    }

    private static func routeDeskFilter(_ event: KeyEvent, context: InputContext) -> InputDecision {
        let modifiers = event.modifiers
        if context.isDeskFilterInputActive {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] { return .perform(.dismissDeskFilter) }
            if event.key == .returnKey, modifiers == [] { return .perform(.confirmDeskFilterQuery) }
            return .forward(.filterTextInput)
        }
        guard modifiers == [] else { return .consume(.exclusiveContext) }
        if event.isEscape { return .perform(.dismissDeskFilter) }
        if event.key == .returnKey { return .perform(.confirmDeskFilterSelection) }
        if event.character?.lowercased() == "/" { return .perform(.enterDeskFilter) }
        return switch (event.key, event.character?.lowercased()) {
        case (.leftArrow, _), (_, "h"): .perform(.selectDeskFilterBoard(-1))
        case (.rightArrow, _), (_, "l"): .perform(.selectDeskFilterBoard(1))
        default: .consume(.exclusiveContext)
        }
    }

    private static func routeDrawer(_ event: KeyEvent, context: InputContext) -> InputDecision {
        if !context.isDenMode, context.isDrawerPreviewFirstResponder { return .forward(.drawerPreview) }
        let modifiers = event.modifiers

        if context.isDrawerFilterInputActive {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] { return .perform(.exitDrawerFilterMode) }
            if event.key == .returnKey, modifiers == [] { return .perform(.confirmDrawerFilterQuery) }
            return .forward(.filterTextInput)
        }
        if context.isDrawerFilterSelecting {
            guard modifiers == [] else { return .consume(.exclusiveContext) }
            if event.isEscape { return .perform(.exitDrawerFilterMode) }
            if event.key == .returnKey { return .perform(.confirmDrawerFilterSelection) }
            return switch (event.key, event.character?.lowercased()) {
            case (.downArrow, _), (_, "j"): .perform(.selectDrawerItem(1))
            case (.upArrow, _), (_, "k"): .perform(.selectDrawerItem(-1))
            default: .consume(.exclusiveContext)
            }
        }

        if context.isDenMode {
            if modifiers == [], event.character?.lowercased() == "u" {
                return event.isRepeat
                    ? .consume(.ignoredRepeat)
                    : .perform(.restoreDiscardedDrawerItem)
            }
            if modifiers == [.shift], event.character?.lowercased() == "d" {
                return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.requestDrawerClearConfirmation)
            }
            guard modifiers == [] else { return .consume(.exclusiveContext) }
            if event.key == .tab { return .perform(.closeDrawer) }
            if event.isEscape { return .perform(.exitDenMode) }
            if event.key == .returnKey {
                return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.toggleSelectedDrawerItem)
            }
            if event.key == .backspace || event.key == .deleteForward {
                return event.isRepeat
                    ? .consume(.ignoredRepeat)
                    : .perform(.discardSelectedDrawerItem(focusNext: true))
            }
            let action: AppAction? =
                switch event.character?.lowercased() {
                case "/": .enterDrawerFilterMode
                case "j": .selectDrawerItem(1)
                case "k": .selectDrawerItem(-1)
                case "p": .placeSelectedDrawerItemAsBoard
                case "x": .discardSelectedDrawerItem(focusNext: false)
                case "d": .discardSelectedDrawerItem(focusNext: true)
                default:
                    switch event.key {
                    case .downArrow: .selectDrawerItem(1)
                    case .upArrow: .selectDrawerItem(-1)
                    default: nil
                    }
                }
            guard let action else { return .consume(.exclusiveContext) }
            if event.isRepeat {
                switch action {
                case .placeSelectedDrawerItemAsBoard, .discardSelectedDrawerItem:
                    return .consume(.ignoredRepeat)
                default:
                    break
                }
            }
            return .perform(action)
        }

        guard modifiers == [] else { return .consume(.exclusiveContext) }
        if event.isEscape { return .perform(.closeDrawer) }
        if event.key == .returnKey {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.toggleSelectedDrawerItem)
        }
        if event.key == .backspace || event.key == .deleteForward {
            return event.isRepeat
                ? .consume(.ignoredRepeat)
                : .perform(.discardSelectedDrawerItem(focusNext: true))
        }
        return switch event.key {
        case .downArrow: .perform(.selectDrawerItem(1))
        case .upArrow: .perform(.selectDrawerItem(-1))
        default: .forward(.temporaryTextInput)
        }
    }

    private static func routeBoardWidth(_ event: KeyEvent) -> InputDecision {
        let modifiers = event.modifiers
        let character = event.character?.lowercased()
        if event.isEscape, modifiers == [] { return .perform(.hideBoardWidthPanel) }
        if character == "w", modifiers == [] {
            return event.isRepeat ? .consume(.ignoredRepeat) : .perform(.hideBoardWidthPanel)
        }
        if character == "-", modifiers == [] { return .perform(.adjustFocusedDeskBoardWidths(-80)) }
        if character == "=", modifiers == [] || modifiers == [.shift] {
            return .perform(.adjustFocusedDeskBoardWidths(80))
        }
        if let count = character.flatMap(Int.init), (1...9).contains(count), modifiers == [] {
            return .perform(.resizeFocusedDeskBoards(count))
        }
        return .consume(.exclusiveContext)
    }

    private static func routeOverview(_ event: KeyEvent, context: InputContext) -> InputDecision {
        let modifiers = event.modifiers
        if context.isOverviewFilterInputActive {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] { return .perform(.exitOverviewFilterMode) }
            if event.key == .returnKey, modifiers == [] { return .perform(.confirmOverviewFilterQuery) }
            return .forward(.filterTextInput)
        }
        if context.isBoardDragging, event.isEscape, modifiers == [] {
            return .perform(.requestBoardDragCancellation)
        }
        if event.isEscape, modifiers == [] {
            return .perform(context.hasOverviewQuery ? .clearOverviewQuery : .hideOverview)
        }
        if event.key == .returnKey, modifiers == [] { return .perform(.enterOverviewSelection) }
        if event.character?.lowercased() == "/", modifiers == [] { return .perform(.enterOverviewFilterMode) }
        if let action = movementAction(event, overview: true) { return .perform(action) }
        return .consume(.exclusiveContext)
    }

    private static func routeZmxSessions(_ event: KeyEvent, context: InputContext) -> InputDecision {
        let modifiers = event.modifiers
        if context.isZmxSessionFilterInputActive {
            if event.hasMarkedText { return .forward(.filterTextInput) }
            if event.isEscape, modifiers == [] { return .perform(.exitZmxSessionFilter) }
            if event.key == .returnKey, modifiers == [] { return .perform(.confirmZmxSessionFilterQuery) }
            return .forward(.filterTextInput)
        }
        guard modifiers == [] else { return .consume(.exclusiveContext) }
        if event.isEscape {
            return .perform(context.hasZmxSessionQuery ? .clearZmxSessionFilter : .hideZmxSessions)
        }
        if event.character?.lowercased() == "/" { return .perform(.enterZmxSessionFilter) }
        if event.key == .upArrow { return .perform(.moveZmxSessionSelection(-1)) }
        if event.key == .downArrow { return .perform(.moveZmxSessionSelection(1)) }
        if event.key == .returnKey { return .perform(.openSelectedZmxSession) }
        if event.key == .backspace || event.key == .deleteForward {
            return .perform(.deleteSelectedZmxSession)
        }
        if event.character?.lowercased() == "x" { return .perform(.deleteSelectedZmxSession) }
        if event.character?.lowercased() == "r" { return .perform(.refreshZmxSessions) }
        return .consume(.exclusiveContext)
    }

    private static func movementAction(_ event: KeyEvent, overview: Bool) -> AppAction? {
        guard event.modifiers == [] || event.modifiers == [.shift], let direction = direction(for: event) else {
            return nil
        }
        return switch (overview, event.modifiers == [.shift], direction) {
        case (false, false, .left): .focusPreviousBoard
        case (false, false, .right): .focusNextBoard
        case (false, false, .upward): .focusPreviousDesk
        case (false, false, .down): .focusNextDesk
        case (false, true, .left): .moveFocusedBoardLeft
        case (false, true, .right): .moveFocusedBoardRight
        case (false, true, .upward): .moveFocusedBoardToPreviousDesk
        case (false, true, .down): .moveFocusedBoardToNextDesk
        case (true, false, .left): .selectPreviousBoardInOverview
        case (true, false, .right): .selectNextBoardInOverview
        case (true, false, .upward): .selectPreviousDeskInOverview
        case (true, false, .down): .selectNextDeskInOverview
        case (true, true, .left): .moveOverviewSelectionBoardLeft
        case (true, true, .right): .moveOverviewSelectionBoardRight
        case (true, true, .upward): .moveOverviewSelectionBoardToPreviousDesk
        case (true, true, .down): .moveOverviewSelectionBoardToNextDesk
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
        binding("i"): KeyboardCommand(action: .toggleNotifications),
        binding("n"): KeyboardCommand(action: .showOpenBoardPanel),
        binding(" "): KeyboardCommand(action: .showOpenBoardPanel),
        binding("v"): KeyboardCommand(action: .openBoardFromClipboard, repeatPolicy: .ignore),
        binding("n", modifiers: [.shift]): KeyboardCommand(action: .showNewDeskPanel),
        binding("p"): KeyboardCommand(action: .showSaveDeskPresetPanel, repeatPolicy: .ignore),
        binding("p", modifiers: [.shift]): KeyboardCommand(action: .showReplaceDeskPanel, repeatPolicy: .ignore),
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
        binding("f", modifiers: [.shift]): KeyboardCommand(action: .toggleFocusMode, repeatPolicy: .ignore),
        binding("c"): KeyboardCommand(action: .centerBoard, repeatPolicy: .ignore),
        binding("t"): KeyboardCommand(action: .toggleFocusedBoardSheetNavigationPause, repeatPolicy: .ignore),
        binding("s"): KeyboardCommand(action: .captureCurrentSheet, repeatPolicy: .ignore),
        binding("s", modifiers: [.shift]): KeyboardCommand(action: .captureFocusedDesk, repeatPolicy: .ignore),
        binding("s", modifiers: [.control]): KeyboardCommand(
            action: .copyCurrentSheetScreenshot, repeatPolicy: .ignore),
        binding("s", modifiers: [.control, .shift]): KeyboardCommand(
            action: .copyFocusedDeskScreenshot, repeatPolicy: .ignore),
        binding("a"): KeyboardCommand(action: .keepCurrentSheetInDrawer, repeatPolicy: .ignore),
        binding("z"): KeyboardCommand(action: .toggleZenView, repeatPolicy: .ignore),
        binding("x"): KeyboardCommand(action: .removeBoard, repeatPolicy: .ignore),
        binding("u"): KeyboardCommand(action: .restoreBoard, repeatPolicy: .ignore),
        binding("r"): KeyboardCommand(action: .showRenameBoardPanel, repeatPolicy: .ignore),
        binding("r", modifiers: [.shift]): KeyboardCommand(action: .showRenameDeskPanel, repeatPolicy: .ignore),
        binding("d"): KeyboardCommand(action: .removeBoardAndFocusNext, repeatPolicy: .ignore),
        binding("d", modifiers: [.shift]): KeyboardCommand(action: .deleteDesk),
        binding("b"): KeyboardCommand(action: .saveFocusedBoardAsEssential, repeatPolicy: .ignore),
        binding("e"): KeyboardCommand(action: .showEditBoardLinkPanel, repeatPolicy: .ignore),
        ShortcutBinding(key: .returnKey, modifiers: [.shift]): KeyboardCommand(
            action: .duplicateFirstSheet, repeatPolicy: .ignore),
        ShortcutBinding(key: .returnKey, modifiers: []): KeyboardCommand(
            action: .duplicateBoard, repeatPolicy: .ignore),
    ]

    private static func binding(
        _ character: String,
        modifiers: ShortcutModifiers = []
    ) -> ShortcutBinding {
        ShortcutBinding(key: .character(character), modifiers: modifiers)
    }
}

@MainActor
enum AppActionHandler {
    static func perform(
        _ action: AppAction,
        store: DenStore?,
        openSettings: () -> Void = {}
    ) {
        if action == .openSettings {
            openSettings()
            return
        }
        guard let store else { return }

        switch action {
        case .openSettings: break
        case .toggleNotifications: store.toggleNotificationList()
        case .closeNotifications: store.closeNotificationList()
        case .moveNotificationSelection(let offset): store.moveNotificationSelection(by: offset)
        case .openSelectedNotification: store.openSelectedNotification()
        case .toggleDenMode: store.toggleDenMode()
        case .exitDenMode: store.exitDenMode()
        case .enterEssentialsPrefix: store.enterEssentialsPrefix()
        case .exitEssentialsPrefix: store.exitEssentialsPrefix()
        case .showEssentialNotFound(let key):
            store.exitEssentialsPrefix()
            let label: String
            switch key {
            case " ": label = "Space"
            case "\r", "\n": label = "Return"
            case "\t": label = "Tab"
            case "\u{8}", "\u{7F}": label = "Delete"
            default: label = key
            }
            store.showToast("No Essential assigned to '\(label)'.", style: .warning)
        case .launchEssential(let id): store.launchEssential(id: id)
        case .focusPreviousDesk: store.focusPreviousDesk()
        case .focusNextDesk: store.focusNextDesk()
        case .returnToPreviousDesk: store.returnToPreviousDesk()
        case .focusPreviousBoard: store.focusPreviousBoard()
        case .focusNextBoard: store.focusNextBoard()
        case .moveFocusedBoardLeft: store.moveFocusedBoardLeft()
        case .moveFocusedBoardRight: store.moveFocusedBoardRight()
        case .moveFocusedBoardToPreviousDesk: store.moveFocusedBoardToPreviousDesk()
        case .moveFocusedBoardToNextDesk: store.moveFocusedBoardToNextDesk()
        case .focusDesk(let number): store.focusDesk(number: number)
        case .moveFocusedBoardToDesk(let number): store.moveFocusedBoard(toDeskNumber: number)
        case .showOpenBoardPanel: store.showOpenBoardPanel()
        case .openBoardFromClipboard: store.openBoardFromClipboard()
        case .hideZmxSessions: store.hideZmxSessions()
        case .enterZmxSessionFilter: store.enterZmxSessionFilter()
        case .exitZmxSessionFilter: store.exitZmxSessionFilter()
        case .confirmZmxSessionFilterQuery: store.confirmZmxSessionFilterQuery()
        case .clearZmxSessionFilter: store.clearZmxSessionFilter()
        case .moveZmxSessionSelection(let offset): store.selectZmxSession(by: offset)
        case .openSelectedZmxSession: store.openSelectedZmxSession()
        case .deleteSelectedZmxSession: store.requestZmxSessionDeletion()
        case .refreshZmxSessions: store.refreshZmxSessions()
        case .showNewDeskPanel: store.showNewDeskPanel()
        case .showSaveDeskPresetPanel: store.showSaveDeskPresetPanel()
        case .showReplaceDeskPanel: store.showReplaceDeskPanel()
        case .showOverview: store.showOverview()
        case .hideOverview: store.hideOverview()
        case .toggleBoardActivity: store.toggleBoardActivity()
        case .hideBoardActivity: store.hideBoardActivity()
        case .enterOverviewSelection: store.enterOverviewSelection()
        case .enterOverviewFilterMode: store.enterOverviewFilterMode()
        case .exitOverviewFilterMode: store.exitOverviewFilterMode()
        case .confirmOverviewFilterQuery: store.confirmOverviewFilterQuery()
        case .clearOverviewQuery: store.clearOverviewQuery()
        case .selectPreviousBoardInOverview: store.selectPreviousBoardInOverview()
        case .selectNextBoardInOverview: store.selectNextBoardInOverview()
        case .selectPreviousDeskInOverview: store.selectPreviousDeskInOverview()
        case .selectNextDeskInOverview: store.selectNextDeskInOverview()
        case .moveOverviewSelectionBoardLeft: store.moveOverviewSelectionBoardLeft()
        case .moveOverviewSelectionBoardRight: store.moveOverviewSelectionBoardRight()
        case .moveOverviewSelectionBoardToPreviousDesk: store.moveOverviewSelectionBoardToPreviousDesk()
        case .moveOverviewSelectionBoardToNextDesk: store.moveOverviewSelectionBoardToNextDesk()
        case .showKeyboardShortcuts: store.showKeyboardShortcuts()
        case .hideKeyboardShortcuts: store.hideKeyboardShortcuts()
        case .showBoardWidthPanel: store.showBoardWidthPanel()
        case .hideBoardWidthPanel: store.hideBoardWidthPanel()
        case .adjustFocusedDeskBoardWidths(let amount): store.adjustFocusedDeskBoardWidths(by: amount)
        case .resizeFocusedDeskBoards(let count): store.resizeFocusedDeskBoards(toFit: count)
        case .toggleDrawer: store.toggleDrawer()
        case .closeDrawer: store.closeDrawer()
        case .enterDrawerFilterMode: store.enterDrawerFilterMode()
        case .exitDrawerFilterMode: store.exitDrawerFilterMode()
        case .confirmDrawerFilterQuery: store.confirmDrawerFilterQuery()
        case .confirmDrawerFilterSelection: store.confirmDrawerFilterSelection()
        case .selectDrawerItem(let offset): store.selectDrawerItem(by: offset)
        case .toggleSelectedDrawerItem: store.toggleSelectedDrawerItem()
        case .discardSelectedDrawerItem(let focusNext):
            store.discardSelectedDrawerItem(focusNext: focusNext)
        case .restoreDiscardedDrawerItem: store.restoreRecentlyDiscardedDrawerItem()
        case .placeSelectedDrawerItemAsBoard: store.placeSelectedDrawerItemAsBoard()
        case .requestDrawerClearConfirmation: store.requestDrawerClearConfirmation()
        case .enterDeskFilter: store.enterDeskFilter()
        case .dismissDeskFilter: store.dismissDeskFilter()
        case .confirmDeskFilterQuery: store.confirmDeskFilterQuery()
        case .confirmDeskFilterSelection: store.confirmDeskFilterSelection()
        case .selectDeskFilterBoard(let offset): store.selectDeskFilterBoard(by: offset)
        case .requestBoardDragCancellation: store.requestBoardDragCancellation()
        case .requestDeskDragCancellation: store.requestDeskDragCancellation()
        case .reloadFocusedBoardFromOrigin: store.reloadFocusedBoardFromOrigin()
        case .reloadFocusedDeskSheets: store.reloadFocusedDeskSheets()
        case .reloadFocusedBoard: store.reloadFocusedBoard()
        case .goBack: store.goBackInFocusedBoard()
        case .goForward: store.goForwardInFocusedBoard()
        case .goToFirstSheet: store.goToFirstSheetInFocusedBoard()
        case .goToLatestSheet: store.goToLatestSheetInFocusedBoard()
        case .adjustBoardWidth(let amount): store.adjustFocusedBoardWidth(by: amount)
        case .toggleBoardMaximized: store.toggleFocusedBoardMaximized()
        case .centerBoard: store.centerFocusedBoard()
        case .revealPreviousBoard: store.revealPreviousBoard()
        case .revealNextBoard: store.revealNextBoard()
        case .toggleFocusedBoardSheetNavigationPause: store.toggleFocusedBoardSheetNavigationPause()
        case .captureCurrentSheet: store.captureFocusedSheetScreenshot()
        case .captureFocusedDesk: store.captureFocusedDeskScreenshot()
        case .copyCurrentSheetScreenshot: store.copyFocusedSheetScreenshot()
        case .copyFocusedDeskScreenshot: store.copyFocusedDeskScreenshot()
        case .keepCurrentSheetInDrawer: store.keepFocusedSheetInDrawer()
        case .toggleZenView: store.toggleZenView()
        case .toggleFocusMode: store.toggleFocusMode()
        case .removeBoard: store.removeFocusedBoard()
        case .removeBoardAndFocusNext: store.removeFocusedBoard(focusNext: true)
        case .restoreBoard: store.restoreRecentlyRemovedBoard()
        case .showRenameBoardPanel: store.showRenameBoardPanel()
        case .showRenameDeskPanel: store.showRenameDeskPanel()
        case .saveFocusedBoardAsEssential: store.saveFocusedBoardAsEssential()
        case .deleteDesk: store.deleteFocusedDesk()
        case .showEditBoardLinkPanel: store.showEditBoardLinkPanel()
        case .duplicateBoard: store.duplicateFocusedBoard()
        case .duplicateFirstSheet: store.duplicateFocusedBoardFromFirstSheet()
        }
    }
}

extension DenStore {
    func performAppAction(_ action: AppAction, openSettings: () -> Void = {}) {
        AppActionHandler.perform(action, store: self, openSettings: openSettings)
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
