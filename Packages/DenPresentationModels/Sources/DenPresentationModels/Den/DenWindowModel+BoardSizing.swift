import DenApplication
import DenDomain
import Foundation

public extension DenWindowModel {
    var defaultBoardWidth: Double {
        inputs.focusedBoard()?.width ?? boardWidth(toFit: 2) ?? BuiltInDeskPreset.boardWidth
    }

    func adjustFocusedBoardWidth(by delta: Double) {
        guard let boardID = inputs.focusedBoard()?.id else { return }
        maximizedBoardID = nil
        boardSizing.adjustBoard(boardID, by: delta)
    }

    func adjustFocusedDeskBoardWidths(by delta: Double) {
        guard let deskID = inputs.focusedDesk()?.id else { return }
        maximizedBoardID = nil
        boardSizing.adjustDesk(deskID, by: delta)
    }

    func updateBoardLayout(availableWidth: Double, spacing: Double) {
        boardLayoutMetrics =
            availableWidth > 0
            ? BoardLayoutMetrics(availableWidth: availableWidth, spacing: spacing)
            : nil
    }

    func boardWidth(toFit count: Int) -> Double? {
        guard let boardLayoutMetrics else { return nil }
        return boardLayoutMetrics.boardWidth(toFit: count)
    }

    func canResizeFocusedDeskBoards(toFit count: Int) -> Bool {
        inputs.focusedDesk()?.boards.isEmpty == false && boardWidth(toFit: count) != nil
    }

    func showBoardWidthPanel() {
        guard inputs.focusedDesk()?.boards.isEmpty == false else { return }
        boardWidthPanelMessage = nil
        setTemporaryContext(.boardWidth)
    }

    func hideBoardWidthPanel() {
        if temporaryContext == .boardWidth { setTemporaryContext(nil) }
    }

    @discardableResult
    func resizeFocusedDeskBoards(toFit count: Int) -> Bool {
        guard let deskID = inputs.focusedDesk()?.id, let width = boardWidth(toFit: count) else {
            boardWidthPanelMessage = "\(count) Boards cannot fit at this window width"
            return false
        }
        guard boardSizing.resizeDesk(deskID, to: width) else { return false }
        maximizedBoardID = nil
        hideBoardWidthPanel()
        centerFocusedBoard()
        return true
    }
}
