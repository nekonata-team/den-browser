import AppKit
import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation
import SwiftUI

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

    // Notifications have no text editor; KeyPress supplies the keys needed by their exclusive context.
    init(notificationKeyPress press: KeyPress) {
        character = String(press.key.character)
        baseCharacter = nil
        characters = press.characters
        key = ShortcutKey(keyEquivalent: String(press.key.character))
        var modifiers: ShortcutModifiers = []
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        self.modifiers = modifiers
        isRepeat = press.phase == .repeat
        hasMarkedText = false
        isEscape = press.key == .escape
    }
}

enum KeyboardMode: Equatable {
    case sheet
    case den
}

enum KeyboardSurface {
    case universalSearch
    case notifications
    case deskFilter(phase: FilterPhase)
    case keyboardShortcuts
    case essentialsPrefix
    case boardWidth
    case overview(filterPhase: FilterPhase, hasQuery: Bool)
    case boardActivity
    case drawer(filterPhase: FilterPhase, peekFirstResponder: Bool)
    case zmxSessions(filterPhase: FilterPhase, hasQuery: Bool, hasSelection: Bool)
    case textInput
}

struct InputContext {
    let isFullscreenActive: Bool
    let hasPendingConfirmation: Bool
    let activeDrag: ActiveDrag?
    let surface: KeyboardSurface?
    let mode: KeyboardMode
    let hasFocusedBoard: Bool
    let focusedBoardIsTerminal: Bool

    init(session: ProfileWindowSession, windowModel: DenWindowModel, event: NSEvent? = nil) {
        isFullscreenActive = windowModel.isFullscreenActive
        hasPendingConfirmation = windowModel.hasPendingConfirmation
        activeDrag = session.resources.data.snapshot.activeDrag
        mode = windowModel.isDenMode ? .den : .sheet
        if windowModel.isNotificationListPresented {
            surface = .notifications
        } else {
            surface =
                switch windowModel.temporaryContext {
                case .universalSearch: .universalSearch
                case .keyboardShortcuts: .keyboardShortcuts
                case .essentialsPrefix: .essentialsPrefix
                case .boardWidth: .boardWidth
                case .overview:
                    .overview(
                        filterPhase: windowModel.overview.filterPhase,
                        hasQuery: !windowModel.overview.query.isEmpty)
                case .boardActivity: .boardActivity
                case .drawer:
                    .drawer(
                        filterPhase: windowModel.drawer.filterPhase,
                        peekFirstResponder: Self.isDrawerPeekFirstResponder(event, session: session))
                case .zmxSessions:
                    .zmxSessions(
                        filterPhase: windowModel.zmxSessions.filterPhase,
                        hasQuery: !windowModel.zmxSessions.query.isEmpty,
                        hasSelection: windowModel.zmxSessions.hasMarkedSessions)
                case .openBoard, .zmxDuplication, .editBoardLink, .newDesk, .replaceDesk, .deskPresetManagement,
                    .saveDeskPreset, .renameBoard, .renameDesk, .saveEssential, .profilePicker:
                    .textInput
                case nil where windowModel.deskFilter.phase != .inactive:
                    .deskFilter(phase: windowModel.deskFilter.phase)
                case nil: nil
                }
        }
        hasFocusedBoard = windowModel.focusedBoard != nil
        focusedBoardIsTerminal = windowModel.focusedBoard?.isTerminal == true
    }

    private static func isDrawerPeekFirstResponder(_ event: NSEvent?, session: ProfileWindowSession) -> Bool {
        guard
            let webView = session.windowResources.drawerPeek?.webView,
            var view = event?.window?.firstResponder as? NSView
        else { return false }

        while view !== webView {
            guard let superview = view.superview else { return false }
            view = superview
        }
        return true
    }
}
