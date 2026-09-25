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

enum KeyboardMode: Equatable {
    case sheet
    case den
}

enum KeyboardSurface {
    case notifications
    case deskFilter(phase: DenFilterPhase)
    case keyboardShortcuts
    case essentialsPrefix
    case boardWidth
    case overview(filterPhase: DenFilterPhase, hasQuery: Bool)
    case boardActivity
    case drawer(filterPhase: DenFilterPhase, previewFirstResponder: Bool)
    case zmxSessions(filterPhase: DenFilterPhase, hasQuery: Bool, hasSelection: Bool)
    case textInput
}

struct InputContext {
    let isFullscreenActive: Bool
    let hasPendingConfirmation: Bool
    let activeDrag: ActiveDrag?
    let surface: KeyboardSurface?
    let mode: KeyboardMode
    let hasFocusedBoard: Bool
    let isProfilePanelPresented: Bool

    init(store: DenStore, event: NSEvent, isProfilePanelPresented: Bool = false) {
        isFullscreenActive = store.isFullscreenActive
        hasPendingConfirmation = store.hasPendingConfirmation
        activeDrag = store.activeDrag
        mode = store.isDenMode ? .den : .sheet
        if store.isNotificationListPresented {
            surface = .notifications
        } else {
            surface =
                switch store.temporaryContext {
                case .keyboardShortcuts: .keyboardShortcuts
                case .essentialsPrefix: .essentialsPrefix
                case .boardWidth: .boardWidth
                case .overview:
                    .overview(filterPhase: store.overviewFilterPhase, hasQuery: !store.overviewQuery.isEmpty)
                case .boardActivity: .boardActivity
                case .drawer:
                    .drawer(
                        filterPhase: store.drawerFilterPhase,
                        previewFirstResponder: Self.isDrawerPreviewFirstResponder(event, store: store))
                case .zmxSessions:
                    .zmxSessions(
                        filterPhase: store.zmxSessions.filterPhase,
                        hasQuery: !store.zmxSessions.query.isEmpty,
                        hasSelection: store.zmxSessions.hasMarkedSessions)
                case .openBoard, .zmxDuplication, .editBoardLink, .newDesk, .replaceDesk, .deskPresetManagement,
                    .saveDeskPreset, .renameBoard, .renameDesk, .saveEssential:
                    .textInput
                case nil where store.deskFilterPhase != .inactive:
                    .deskFilter(phase: store.deskFilterPhase)
                case nil: nil
                }
        }
        hasFocusedBoard = store.focusedBoard != nil
        self.isProfilePanelPresented = isProfilePanelPresented
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
