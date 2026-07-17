import AppKit
import Foundation

@MainActor
final class KeyboardController {
    private var monitor: Any?

    func start(profileManager: ProfileManager, preferences: AppPreferences) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak profileManager, weak preferences] event in
            guard let store = profileManager?.activeStore(), let preferences else { return event }
            return Self.handle(event, store: store, preferences: preferences) ? nil : event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    static func handle(_ event: NSEvent, store: DenStore, preferences: AppPreferences? = nil) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        let character = characterIgnoringModifiers(for: event)

        if character == "q", modifiers == [.command] {
            return false
        }

        if store.deskPendingDeletion != nil {
            return false
        }

        if store.isBoardDragging {
            if isEscape(event), modifiers == [] {
                store.requestBoardDragCancellation()
            }
            return true
        }

        if character == "w", modifiers == [.command] {
            if !event.isARepeat {
                store.removeFocusedBoard()
            }
            return true
        }

        if character == "w", modifiers == [.command, .shift] {
            return false
        }

        if character == "t", modifiers == [.command] {
            store.showOpenBoardPanel()
            return true
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
        case .openBoard, .newDesk, .saveDeskTemplate:
            return false
        case nil:
            break
        }

        if !store.isDenMode, character == "r", modifiers == [.command] {
            store.reloadFocusedBoard()
            return true
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
        _ event: NSEvent,
        store: DenStore,
        preferences: AppPreferences?
    ) -> Bool {
        guard let binding = ShortcutBinding(event: event) else { return false }
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
            if !event.isARepeat { store.toggleDenMode() }
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

    private static func handleDenMode(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if isEscape(event), modifiers == [] {
            store.exitDenMode()
            return true
        }

        if handleMovement(event, modifiers: modifiers, store: store, overview: false) {
            return true
        }

        if isQuestionMark(event, modifiers: modifiers) {
            store.showKeyboardShortcuts()
            return true
        }

        let character = characterIgnoringModifiers(for: event)
        if let digit = character.flatMap(Int.init), (0...9).contains(digit) {
            let deskNumber = digit == 0 ? 10 : digit
            if modifiers == [] {
                store.focusDesk(number: deskNumber)
            } else if modifiers == [.shift] {
                store.moveFocusedBoard(toDeskNumber: deskNumber)
            }
            return true
        }

        switch (character, modifiers) {
        case ("n", []), (" ", []):
            store.showOpenBoardPanel()
        case ("n", [.shift]):
            store.showNewDeskPanel()
        case ("b", []):
            if !event.isARepeat {
                store.showSaveDeskTemplatePanel()
            }
        case ("o", []):
            store.showOverview()
        case ("w", []):
            if !event.isARepeat {
                store.showBoardWidthPanel()
            }
        case ("[", []):
            store.goBackInFocusedBoard()
        case ("]", []):
            store.goForwardInFocusedBoard()
        case ("-", []):
            store.adjustFocusedBoardWidth(by: -80)
        case ("=", []), ("=", [.shift]):
            store.adjustFocusedBoardWidth(by: 80)
        case ("f", []):
            if !event.isARepeat {
                store.toggleFocusedBoardMaximized()
            }
        case ("c", []):
            if !event.isARepeat {
                store.centerFocusedBoard()
            }
        case ("z", []):
            if !event.isARepeat {
                store.toggleZenView()
            }
        case ("x", []):
            if !event.isARepeat {
                store.removeFocusedBoard()
            }
        case ("u", []):
            if !event.isARepeat {
                store.restoreRecentlyRemovedBoard()
            }
        case ("d", []):
            if !event.isARepeat {
                store.removeFocusedBoard()
            }
        case ("d", [.shift]):
            store.deleteFocusedDesk()
        default:
            if isReturn(event), modifiers == [] {
                store.duplicateFocusedBoard()
            }
        }

        return true
    }

    private static func handleBoardWidthPanel(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if isEscape(event), modifiers == [] {
            store.hideBoardWidthPanel()
            return true
        }

        let character = characterIgnoringModifiers(for: event)
        if character == "w", modifiers == [], !event.isARepeat {
            store.hideBoardWidthPanel()
        } else if let count = character.flatMap(Int.init), (1...9).contains(count), modifiers == [] {
            store.resizeFocusedDeskBoards(toFit: count)
        }
        return true
    }

    private static func handleOverview(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if isEscape(event), modifiers == [] {
            store.hideOverview()
            return true
        }

        if handleMovement(event, modifiers: modifiers, store: store, overview: true) {
            return true
        }
        if isReturn(event), modifiers == [] {
            store.enterOverviewSelection()
        }
        return true
    }

    private static func handleMovement(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        store: DenStore,
        overview: Bool
    ) -> Bool {
        guard modifiers == [] || modifiers == [.shift], let direction = movementDirection(for: event) else {
            return false
        }

        switch (overview, modifiers == [.shift], direction) {
        case (false, false, .left): store.focusPreviousBoard()
        case (false, false, .right): store.focusNextBoard()
        case (false, false, .up): store.focusPreviousDesk()
        case (false, false, .down): store.focusNextDesk()
        case (false, true, .left): store.moveFocusedBoardLeft()
        case (false, true, .right): store.moveFocusedBoardRight()
        case (false, true, .up): store.moveFocusedBoardToPreviousDesk()
        case (false, true, .down): store.moveFocusedBoardToNextDesk()
        case (true, false, .left): store.selectPreviousBoardInOverview()
        case (true, false, .right): store.selectNextBoardInOverview()
        case (true, false, .up): store.selectPreviousDeskInOverview()
        case (true, false, .down): store.selectNextDeskInOverview()
        case (true, true, .left): store.moveOverviewSelectionBoardLeft()
        case (true, true, .right): store.moveOverviewSelectionBoardRight()
        case (true, true, .up): store.moveOverviewSelectionBoardToPreviousDesk()
        case (true, true, .down): store.moveOverviewSelectionBoardToNextDesk()
        }
        return true
    }

    private static func movementDirection(for event: NSEvent) -> MovementDirection? {
        switch event.specialKey {
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .upArrow: return .up
        case .downArrow: return .down
        default:
            switch characterIgnoringModifiers(for: event) {
            case "h": return .left
            case "l": return .right
            case "k": return .up
            case "j": return .down
            default: return nil
            }
        }
    }

    private static func normalizedModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .control, .option, .shift])
    }

    private static func characterIgnoringModifiers(for event: NSEvent) -> String? {
        event.charactersIgnoringModifiers?.lowercased()
    }

    private static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53
    }

    private static func isQuestionMark(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers == [.shift]
            && (event.characters == "?" || event.charactersIgnoringModifiers == "/")
    }

    private static func isReturn(_ event: NSEvent) -> Bool {
        event.specialKey == .carriageReturn
    }
}

private enum MovementDirection {
    case left
    case right
    case up
    case down
}
