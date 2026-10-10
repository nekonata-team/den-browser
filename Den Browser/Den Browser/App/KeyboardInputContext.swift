import AppKit
import DenApplication
import DenPresentationModels
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
    case deskFilter(phase: FilterPhase)
    case keyboardShortcuts
    case essentialsPrefix
    case boardWidth
    case overview(filterPhase: FilterPhase, hasQuery: Bool)
    case boardActivity
    case drawer(filterPhase: FilterPhase, previewFirstResponder: Bool)
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

    init(controller: DenController, windowModel: DenWindowModel, event: NSEvent) {
        isFullscreenActive = windowModel.isFullscreenActive
        hasPendingConfirmation = windowModel.hasPendingConfirmation
        activeDrag = controller.activeDrag
        mode = windowModel.isDenMode ? .den : .sheet
        if windowModel.isNotificationListPresented {
            surface = .notifications
        } else {
            surface =
                switch windowModel.temporaryContext {
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
                        previewFirstResponder: Self.isDrawerPreviewFirstResponder(event, controller: controller))
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
        hasFocusedBoard = controller.focusedBoard != nil
    }

    private static func isDrawerPreviewFirstResponder(_ event: NSEvent, controller: DenController) -> Bool {
        guard
            let webView = controller.drawerPreviewRuntime?.webView,
            var view = event.window?.firstResponder as? NSView
        else { return false }

        while view !== webView {
            guard let superview = view.superview else { return false }
            view = superview
        }
        return true
    }
}
