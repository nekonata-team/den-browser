import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
enum UniversalSearchActions {
    static func perform(
        _ target: UniversalSearchItem.Target,
        controller: DenController,
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
                controller.storage.data.snapshot.den.desks.contains(where: {
                    $0.boards.contains(where: { $0.id == id })
                })
            else {
                return "This Board is no longer available."
            }
            windowModel.hideUniversalSearch()
            controller.focusBoard(id, exitsDenMode: true)
        case .desk(let id):
            guard controller.storage.data.snapshot.den.desks.contains(where: { $0.id == id }) else {
                return "This Desk is no longer available."
            }
            windowModel.hideUniversalSearch()
            controller.focusDesk(id)
        case .profile(let id):
            guard openProfile(id) else {
                return "This Profile could not be opened."
            }
            windowModel.hideUniversalSearch()
        case .essential(let id):
            guard let essential = controller.preferences.essentials.first(where: { $0.id == id }) else {
                return "This Essential is no longer available."
            }
            return open(essential.input, controller: controller, windowModel: windowModel, inDrawer: inDrawer)
        case .recent(let item):
            guard controller.storage.data.snapshot.recentItems.contains(item) else {
                return "This Recent Item is no longer available."
            }
            return open(item.displayText, controller: controller, windowModel: windowModel, inDrawer: inDrawer)
        case .createBoard(let input):
            return open(input, controller: controller, windowModel: windowModel, inDrawer: inDrawer)
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
                action, controller: controller, windowModel: windowModel, openSettings: openSettings)
        }
        return nil
    }

    private static func open(
        _ input: String, controller: DenController, windowModel: DenWindowModel, inDrawer: Bool
    ) -> String? {
        if inDrawer { return controller.openInDrawer(input: input) }
        switch controller.requestOpenBoard(input: input, preferredWidth: windowModel.defaultBoardWidth) {
        case .accepted:
            windowModel.hideUniversalSearch()
            return nil
        case .rejected(let message):
            return message ?? "Could not create a Board from this input."
        }
    }
}
