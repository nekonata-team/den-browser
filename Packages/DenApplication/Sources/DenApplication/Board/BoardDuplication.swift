import DenDomain

public enum BoardDuplication {
    public enum Decision {
        case create(BoardState)
        case zmxSession
        case unavailable
    }

    public static func resolve(_ source: BoardState, fromFirstSheet: Bool = false) -> Decision {
        guard !source.isSideBoard, !source.isTutorial else { return .unavailable }
        if source.isZmx { return .zmxSession }
        if let directory = source.terminalWorkingDirectory {
            return .create(
                BoardState(
                    label: source.label, width: source.width, workingDirectory: directory,
                    customLabel: source.customLabel))
        }
        if source.isZellij {
            return .create(
                BoardState(
                    label: source.label, width: source.width, zellijSessionName: source.zellijSessionName,
                    customLabel: source.customLabel))
        }
        if fromFirstSheet && source.firstSheetURL == nil { return .unavailable }
        return .create(
            BoardState(
                label: source.label, width: source.width,
                currentSheetURL: fromFirstSheet ? source.firstSheetURL : source.currentSheetURL,
                firstSheetURL: fromFirstSheet ? source.firstSheetURL : nil,
                customLabel: source.customLabel, sheetNavigationPaused: source.sheetNavigationPaused))
    }
}
