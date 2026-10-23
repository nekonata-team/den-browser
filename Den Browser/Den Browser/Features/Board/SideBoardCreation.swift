import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation

@MainActor
final class SideBoardCreation {
    private let context: WindowNativeContext
    private let boardNavigation: BoardNavigation
    private let boardOpening: BoardOpeningActions
    private let zmx: ZmxBoardActions
    private var runtimes: BoardRuntimeAccess { context.runtimes }
    private var state: DenState { context.storage.state }

    init(
        context: WindowNativeContext, boardNavigation: BoardNavigation, boardOpening: BoardOpeningActions,
        zmx: ZmxBoardActions
    ) {
        self.context = context
        self.boardNavigation = boardNavigation
        self.boardOpening = boardOpening
        self.zmx = zmx
    }

    @discardableResult
    func createInspectionBoard(targetBoardID: BoardID, focus: Bool = true) -> BoardID? {
        guard let indices = context.boardIndices(for: targetBoardID) else { return nil }
        let targetBoard = state.desks[indices.deskOffset].boards[indices.boardOffset]
        guard targetBoard.isWeb else { return nil }
        if let existingSideBoard = state.desks[indices.deskOffset].boards.first(where: {
            $0.sideBoardTargetBoardID == targetBoardID
        }) {
            guard existingSideBoard.isInspection else { return nil }
            if focus { boardNavigation.focusBoard(existingSideBoard.id, exitsDenMode: true) }
            if !focus { runtimes.webRuntime(for: targetBoard).startInspectionCollection(highlightColor: nil) }
            return existingSideBoard.id
        }
        let board = BoardState(
            width: DenLayout.sideBoardInitialWidth,
            targetBoardID: targetBoardID
        )
        let targetRuntime = focus ? nil : runtimes.webRuntime(for: targetBoard)
        guard
            boardOpening.insertBoard(
                board, afterBoardID: targetBoardID, focus: focus, origin: focus ? .interactive : .cli)
        else {
            return nil
        }
        targetRuntime?.startInspectionCollection(highlightColor: nil)
        return board.id
    }

    @discardableResult
    func createTerminalSideBoard(targetBoardID: BoardID, focus: Bool = true) -> BoardID? {
        guard let requestedIndices = context.boardIndices(for: targetBoardID) else { return nil }
        let requestedBoard = state.desks[requestedIndices.deskOffset].boards[requestedIndices.boardOffset]
        let primaryBoardID = requestedBoard.sideBoardTargetBoardID ?? requestedBoard.id
        guard let indices = context.boardIndices(for: primaryBoardID) else { return nil }
        let primaryBoard = state.desks[indices.deskOffset].boards[indices.boardOffset]
        guard primaryBoard.isTerminal else { return nil }

        if let existingSideBoard = state.desks[indices.deskOffset].boards.first(where: {
            $0.sideBoardTargetBoardID == primaryBoardID
        }) {
            guard existingSideBoard.isTerminal else { return nil }
            if focus { boardNavigation.focusBoard(existingSideBoard.id, exitsDenMode: true) }
            return existingSideBoard.id
        }

        if primaryBoard.isZmx {
            zmx.createZmxBoard(from: primaryBoard, suffix: "", asSideBoard: true, focus: focus)
            return nil
        }

        let workingDirectory =
            primaryBoard.terminalWorkingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        var board = BoardState(
            label: "Terminal Side Board", width: DenLayout.sideBoardInitialWidth, workingDirectory: workingDirectory)
        board.role = .sideBoard(targetBoardID: primaryBoardID)
        guard
            boardOpening.insertBoard(
                board,
                afterBoardID: primaryBoardID,
                focus: focus,
                origin: focus ? .interactive : .cli)
        else { return nil }
        return board.id
    }
}
