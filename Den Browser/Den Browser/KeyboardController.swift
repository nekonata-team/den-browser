import AppKit
import Foundation

@MainActor
final class KeyboardController {
    private var monitor: Any?

    func start(profileManager: ProfileManager) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak profileManager] event in
            guard let store = profileManager?.activeStore() else { return event }
            return Self.handle(event, store: store) ? nil : event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    static func handle(_ event: NSEvent, store: DenStore) -> Bool {
        if characterIgnoringModifiers(for: event) == "t", normalizedModifiers(for: event) == [.command] {
            store.showOpenBoardPanel()
            return true
        }

        if store.isOverviewPresented {
            return handleOverview(event, store: store)
        }

        if store.isOpenBoardPanelPresented || store.isNewDeskPanelPresented {
            return false
        }

        if isDenModeToggle(event), normalizedModifiers(for: event) == [.control] {
            if !event.isARepeat {
                store.toggleDenMode()
            }
            return true
        }

        if store.isDenMode {
            return handleDenMode(event, store: store)
        }

        return handleSheetInput(event, store: store)
    }

    private static func handleSheetInput(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if characterIgnoringModifiers(for: event) == "r", modifiers == [.command] {
            store.reloadFocusedBoard()
            return true
        }

        return false
    }

    private static func handleDenMode(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if characterIgnoringModifiers(for: event) == "q", modifiers == [.command] {
            return false
        }

        if isEscape(event), modifiers == [] {
            if store.heldBoard == nil {
                store.exitDenMode()
            } else {
                store.restoreHeldBoard()
            }
            return true
        }

        if handleMovement(event, modifiers: modifiers, store: store) {
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
        case ("n", []):
            store.showOpenBoardPanel()
        case ("n", [.shift]):
            store.showNewDeskPanel()
        case ("o", []):
            store.showOverview()
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
        case ("x", []):
            store.holdFocusedBoard()
        case ("p", []):
            store.placeHeldBoard()
        case ("p", [.shift]):
            store.placeHeldBoard(beforeFocusedBoard: true)
        case ("u", []):
            store.restoreHeldBoard()
        case ("d", []):
            store.closeFocusedBoard()
        case ("d", [.shift]):
            store.deleteFocusedDesk()
        default:
            if isReturn(event), modifiers == [] {
                store.duplicateFocusedBoard()
            }
        }

        return true
    }

    private static func handleOverview(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        if isEscape(event), modifiers == [] {
            store.hideOverview()
            return true
        }

        switch (event.specialKey, modifiers) {
        case (.leftArrow, []):
            store.selectPreviousBoardInOverview()
        case (.rightArrow, []):
            store.selectNextBoardInOverview()
        case (.upArrow, []):
            store.selectPreviousDeskInOverview()
        case (.downArrow, []):
            store.selectNextDeskInOverview()
        case (.leftArrow, [.shift]):
            store.moveOverviewSelectionBoardLeft()
        case (.rightArrow, [.shift]):
            store.moveOverviewSelectionBoardRight()
        case (.upArrow, [.shift]):
            store.moveOverviewSelectionBoardToPreviousDesk()
        case (.downArrow, [.shift]):
            store.moveOverviewSelectionBoardToNextDesk()
        case (.carriageReturn, []):
            store.enterOverviewSelection()
        default:
            return handleOverviewCharacter(event, modifiers: modifiers, store: store)
        }

        return true
    }

    private static func handleOverviewCharacter(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        store: DenStore
    ) -> Bool {
        switch (characterIgnoringModifiers(for: event), modifiers) {
        case ("h", []):
            store.selectPreviousBoardInOverview()
        case ("l", []):
            store.selectNextBoardInOverview()
        case ("j", []):
            store.selectNextDeskInOverview()
        case ("k", []):
            store.selectPreviousDeskInOverview()
        case ("h", [.shift]):
            store.moveOverviewSelectionBoardLeft()
        case ("l", [.shift]):
            store.moveOverviewSelectionBoardRight()
        case ("j", [.shift]):
            store.moveOverviewSelectionBoardToNextDesk()
        case ("k", [.shift]):
            store.moveOverviewSelectionBoardToPreviousDesk()
        default:
            break
        }

        return true
    }

    private static func handleMovement(_ event: NSEvent, modifiers: NSEvent.ModifierFlags, store: DenStore) -> Bool {
        switch (event.specialKey, modifiers) {
        case (.leftArrow, []):
            store.focusPreviousBoard()
        case (.rightArrow, []):
            store.focusNextBoard()
        case (.upArrow, []):
            store.focusPreviousDesk()
        case (.downArrow, []):
            store.focusNextDesk()
        case (.leftArrow, [.shift]):
            store.moveFocusedBoardLeft()
        case (.rightArrow, [.shift]):
            store.moveFocusedBoardRight()
        case (.upArrow, [.shift]):
            store.moveFocusedBoardToPreviousDesk()
        case (.downArrow, [.shift]):
            store.moveFocusedBoardToNextDesk()
        default:
            return handleMovementCharacter(event, modifiers: modifiers, store: store)
        }

        return true
    }

    private static func handleMovementCharacter(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        store: DenStore
    ) -> Bool {
        switch (characterIgnoringModifiers(for: event), modifiers) {
        case ("h", []):
            store.focusPreviousBoard()
        case ("l", []):
            store.focusNextBoard()
        case ("j", []):
            store.focusNextDesk()
        case ("k", []):
            store.focusPreviousDesk()
        case ("h", [.shift]):
            store.moveFocusedBoardLeft()
        case ("l", [.shift]):
            store.moveFocusedBoardRight()
        case ("j", [.shift]):
            store.moveFocusedBoardToNextDesk()
        case ("k", [.shift]):
            store.moveFocusedBoardToPreviousDesk()
        default:
            return false
        }

        return true
    }

    private static func normalizedModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .control, .option, .shift])
    }

    private static func characterIgnoringModifiers(for event: NSEvent) -> String? {
        event.charactersIgnoringModifiers?.lowercased()
    }

    private static func isDenModeToggle(_ event: NSEvent) -> Bool {
        event.characters == "," || event.charactersIgnoringModifiers == ","
    }

    private static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53
    }

    private static func isReturn(_ event: NSEvent) -> Bool {
        event.specialKey == .carriageReturn
    }
}
