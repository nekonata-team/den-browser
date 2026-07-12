import AppKit
import Foundation

@MainActor
final class KeyboardController {
    private var monitor: Any?

    func start(store: DenStore) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak store] event in
            guard let store else { return event }
            return Self.handle(event, store: store) ? nil : event
        }
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    private static func handle(_ event: NSEvent, store: DenStore) -> Bool {
        if store.isOverviewPresented {
            return handleOverview(event, store: store)
        }

        return handleDenShortcut(event, store: store)
    }

    private static func handleOverview(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
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
            if isEscape(event), modifiers == [] {
                store.hideOverview()
                return true
            }
            return handleDenShortcut(event, store: store)
        }

        return true
    }

    private static func handleDenShortcut(_ event: NSEvent, store: DenStore) -> Bool {
        let modifiers = normalizedModifiers(for: event)
        let denModifiers: NSEvent.ModifierFlags = [.control, .option]
        let denShiftModifiers: NSEvent.ModifierFlags = [.control, .option, .shift]

        switch (event.specialKey, modifiers) {
        case (.leftArrow, denModifiers):
            store.focusPreviousBoard()
        case (.rightArrow, denModifiers):
            store.focusNextBoard()
        case (.upArrow, denModifiers):
            store.focusPreviousDesk()
        case (.downArrow, denModifiers):
            store.focusNextDesk()
        case (.leftArrow, denShiftModifiers):
            store.moveFocusedBoardLeft()
        case (.rightArrow, denShiftModifiers):
            store.moveFocusedBoardRight()
        case (.upArrow, denShiftModifiers):
            store.moveFocusedBoardToPreviousDesk()
        case (.downArrow, denShiftModifiers):
            store.moveFocusedBoardToNextDesk()
        case (.carriageReturn, denModifiers):
            store.duplicateFocusedBoard()
        default:
            return handleCharacterShortcut(event, modifiers: modifiers, store: store)
        }

        return true
    }

    private static func handleCharacterShortcut(_ event: NSEvent, modifiers: NSEvent.ModifierFlags, store: DenStore)
        -> Bool
    {
        guard let character = event.charactersIgnoringModifiers?.lowercased() else { return false }

        if modifiers == [.command], character == "r" {
            store.reloadFocusedBoard()
            return true
        }

        guard modifiers == [.control, .option] else { return false }

        switch character {
        case " ":
            store.showOpenBoardPanel()
        case "o":
            store.toggleOverview()
        case "n":
            store.showNewDeskPanel()
        case "[":
            store.goBackInFocusedBoard()
        case "]":
            store.goForwardInFocusedBoard()
        case "-":
            store.adjustFocusedBoardWidth(by: -80)
        case ";":
            store.adjustFocusedBoardWidth(by: 80)
        case "w":
            store.closeFocusedBoard()
        case "h":
            store.holdFocusedBoard()
        case "p":
            store.placeHeldBoard()
        default:
            return false
        }

        return true
    }

    private static func normalizedModifiers(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    private static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53
    }
}
