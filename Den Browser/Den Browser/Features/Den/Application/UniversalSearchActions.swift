import DenApplication
import DenDomain
import DenModels
import Foundation

@MainActor
enum UniversalSearchActions {
    static func shortcut(
        for command: UniversalSearchCommand,
        configuration: ShortcutConfiguration
    ) -> (binding: ShortcutBinding, denModeOnly: Bool)? {
        if command == .openProfile {
            // The native Open Profile menu shortcut is reached only if the key router does not claim it.
            let binding = ShortcutBinding.openProfile
            guard configuration.shortcut(matching: binding) == nil else { return nil }
            return (binding, false)
        }
        guard let action = action(for: command), let binding = KeyboardRouter.denModeShortcut(for: action) else {
            return nil
        }
        return (binding, true)
    }

    static func perform(
        _ target: UniversalSearchItem.Target,
        session: ProfileWindowSession,
        windowModel: DenWindowModel,
        inDrawer: Bool = false,
        openProfile: (ProfileID) -> Bool,
        openSettings: () -> Void
    ) -> String? {
        if inDrawer {
            switch target {
            case .essential, .createBoard: break
            default: return "Choose a URL, search, or Essential to open in Drawer."
            }
        }
        switch target {
        case .board(let id):
            guard target.boardDesk(in: session.resources.state) != nil else {
                return "This Board is no longer available."
            }
            windowModel.hideUniversalSearch()
            session.boardNavigation.focusBoard(id, exitsDenMode: true)
        case .drawerItem(let id):
            guard windowModel.focusDrawerItem(id) else {
                return "This Drawer Item is no longer available."
            }
        case .desk(let id):
            guard target.desk(in: session.resources.state) != nil else {
                return "This Desk is no longer available."
            }
            windowModel.hideUniversalSearch()
            session.boardNavigation.focusDesk(id)
        case .profile(let id):
            guard openProfile(id) else {
                return "This Profile could not be opened."
            }
            windowModel.hideUniversalSearch()
        case .builtInDeskPreset(let preset):
            windowModel.hideUniversalSearch()
            windowModel.showNewDeskPanel(preset: .builtIn(preset))
        case .personalDeskPreset(let id):
            windowModel.hideUniversalSearch()
            windowModel.showNewDeskPanel(preset: .personal(id))
        case .essential, .recent, .createBoard:
            guard
                let input = target.creationInput(
                    essentials: session.configuration.preferences.essentials,
                    recents: session.resources.recentItems
                )
            else {
                if case .essential = target { return "This Essential is no longer available." }
                return "This Recent Item is no longer available."
            }
            return open(input, session: session, windowModel: windowModel, inDrawer: inDrawer)
        case .command(let command):
            windowModel.hideUniversalSearch()
            guard let action = action(for: command) else {
                windowModel.setTemporaryContext(.profilePicker)
                return nil
            }
            AppActionHandler.perform(
                action,
                session: session,
                windowModel: windowModel,
                openSettings: openSettings
            )
        }
        return nil
    }

    private static func action(for command: UniversalSearchCommand) -> AppAction? {
        switch command {
        case .newDesk: .desk(.showNewPanel)
        case .openProfile: nil
        case .openSettings: .application(.openSettings)
        case .toggleZenView: .application(.toggleZenView)
        case .toggleFocusMode: .application(.toggleFocusMode)
        case .undoBoardOperation: .board(.undo)
        case .showKeyboardShortcuts: .application(.showKeyboardShortcuts)
        }
    }

    private static func open(
        _ input: String,
        session: ProfileWindowSession,
        windowModel: DenWindowModel,
        inDrawer: Bool
    ) -> String? {
        if inDrawer { return session.input.openInDrawer(input: input) }
        switch session.boardOpening.requestOpenBoard(input: input, preferredWidth: windowModel.defaultBoardWidth) {
        case .accepted:
            windowModel.hideUniversalSearch()
            return nil
        case .rejected(let message):
            return message ?? "Could not create a Board from this input."
        }
    }
}
