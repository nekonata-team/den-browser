import DenDomain
import Foundation

extension UniversalSearchModel {
    public static func sourceItems(
        state: DenState, essentials: [Essential], hasBoardUndoHistory: Bool,
        profiles: [ProfileState], profileName: String
    ) -> [UniversalSearchItem] {
        var items: [UniversalSearchItem] = []
        for desk in state.desks {
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
        items += essentials.map {
            UniversalSearchItem(
                target: .essential($0.id), title: $0.name,
                detail: "Create Board from Essential · \($0.displayKey)", keywords: $0.input)
        }
        items += state.desks.map {
            UniversalSearchItem(target: .desk($0.id), title: $0.label, detail: "Switch to Desk · \(profileName)")
        }
        items += profiles.map {
            UniversalSearchItem(target: .profile($0.id), title: $0.name, detail: "Switch to Profile")
        }
        for command in UniversalSearchCommand.allCases {
            if command == .undoBoardOperation, !hasBoardUndoHistory { continue }
            let title: String
            switch command {
            case .newDesk: title = "New Desk…"
            case .openProfile: title = "Open Profile…"
            case .openSettings: title = "Open Settings"
            case .toggleZenView: title = "Toggle Zen View"
            case .toggleFocusMode: title = "Toggle Focus Mode"
            case .undoBoardOperation: title = "Undo Board Operation"
            }
            items.append(UniversalSearchItem(target: .command(command), title: title, detail: "Command"))
        }
        return items
    }
}
