import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
enum UniversalSearchActions {
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
            guard
                session.resources.data.snapshot.den.desks.contains(where: {
                    $0.boards.contains(where: { $0.id == id })
                })
            else {
                return "This Board is no longer available."
            }
            windowModel.hideUniversalSearch()
            session.boardNavigation.focusBoard(id, exitsDenMode: true)
        case .desk(let id):
            guard session.resources.data.snapshot.den.desks.contains(where: { $0.id == id }) else {
                return "This Desk is no longer available."
            }
            windowModel.hideUniversalSearch()
            session.boardNavigation.focusDesk(id)
        case .profile(let id):
            guard openProfile(id) else {
                return "This Profile could not be opened."
            }
            windowModel.hideUniversalSearch()
        case .essential(let id):
            guard let essential = session.configuration.preferences.essentials.first(where: { $0.id == id }) else {
                return "This Essential is no longer available."
            }
            return open(essential.input, session: session, windowModel: windowModel, inDrawer: inDrawer)
        case .recent(let item):
            guard session.resources.data.snapshot.recentItems.contains(item) else {
                return "This Recent Item is no longer available."
            }
            return open(item.displayText, session: session, windowModel: windowModel, inDrawer: inDrawer)
        case .createBoard(let input):
            return open(input, session: session, windowModel: windowModel, inDrawer: inDrawer)
        case .command(let command):
            windowModel.hideUniversalSearch()
            let action: AppAction
            switch command {
            case .newDesk: action = .desk(.showNewPanel)
            case .openProfile:
                windowModel.setTemporaryContext(.profilePicker)
                return nil
            case .openSettings: action = .application(.openSettings)
            case .toggleZenView: action = .application(.toggleZenView)
            case .toggleFocusMode: action = .application(.toggleFocusMode)
            case .restoreBoard: action = .board(.restore)
            }
            AppActionHandler.perform(
                action, session: session, windowModel: windowModel, openSettings: openSettings)
        }
        return nil
    }

    private static func open(
        _ input: String, session: ProfileWindowSession, windowModel: DenWindowModel, inDrawer: Bool
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
