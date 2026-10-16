import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
enum UniversalSearchActions {
    static func items(controller: DenController, profiles: [ProfileState], profileName: String) -> [UniversalSearchItem]
    {
        var items: [UniversalSearchItem] = []
        for desk in controller.state.desks {
            for board in desk.boards {
                items.append(
                    UniversalSearchItem(
                        target: .board(board.id), title: board.displayName,
                        detail: "Switch to Board · \(profileName) / \(desk.label)",
                        keywords: [
                            board.currentSheetURL?.absoluteString, board.terminalWorkingDirectory,
                            board.zellijSessionName, board.zmxSessionName,
                        ].compactMap { $0 }.joined(separator: " ")))
            }
        }
        items += controller.essentials.map {
            UniversalSearchItem(
                target: .essential($0.id), title: $0.name,
                detail: "Create Board from Essential · \($0.displayKey)", keywords: $0.input)
        }
        items += controller.state.desks.map {
            UniversalSearchItem(target: .desk($0.id), title: $0.label, detail: "Switch to Desk · \(profileName)")
        }
        items += profiles.map {
            UniversalSearchItem(target: .profile($0.id), title: $0.name, detail: "Switch to Profile")
        }
        for command in UniversalSearchCommand.allCases {
            if command == .restoreBoard, controller.recentlyRemovedBoards.isEmpty { continue }
            let title: String
            switch command {
            case .newDesk: title = "New Desk…"
            case .openProfile: title = "Open Profile…"
            case .openSettings: title = "Open Settings"
            case .toggleZenView: title = "Toggle Zen View"
            case .toggleFocusMode: title = "Toggle Focus Mode"
            case .restoreBoard: title = "Restore Recently Removed Board"
            }
            items.append(UniversalSearchItem(target: .command(command), title: title, detail: "Command"))
        }
        return items
    }

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
            guard controller.state.desks.contains(where: { $0.boards.contains(where: { $0.id == id }) }) else {
                return "This Board is no longer available."
            }
            windowModel.hideUniversalSearch()
            controller.focusBoard(id, exitsDenMode: true)
        case .desk(let id):
            guard controller.state.desks.contains(where: { $0.id == id }) else {
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
            guard let essential = controller.essentials.first(where: { $0.id == id }) else {
                return "This Essential is no longer available."
            }
            return open(essential.input, controller: controller, windowModel: windowModel, inDrawer: inDrawer)
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
