import DenDesign
import DenDomain
import DenPresentation
import Foundation

extension DenWindowModel {
    var defaultBoardWidth: Double {
        focusedBoard()?.width ?? boardWidth(toFit: 2) ?? BuiltInDeskPreset.boardWidth
    }

    func adjustFocusedBoardWidth(by delta: Double) {
        guard let boardID = focusedBoard()?.id else { return }
        maximizedBoardID = nil
        boardActions.adjustBoardWidth(boardID, delta)
    }

    func adjustFocusedDeskBoardWidths(by delta: Double) {
        guard let deskID = focusedDesk()?.id else { return }
        maximizedBoardID = nil
        boardActions.adjustDeskBoardWidths(deskID, delta)
    }

    func updateBoardLayout(availableWidth: Double, spacing: Double) {
        boardLayoutMetrics =
            availableWidth > 0
            ? BoardLayoutMetrics(availableWidth: availableWidth, spacing: spacing)
            : nil
    }

    func boardWidth(toFit count: Int) -> Double? {
        guard let boardLayoutMetrics else { return nil }
        return DenLayout.boardWidth(
            toFit: count,
            in: boardLayoutMetrics.availableWidth,
            spacing: boardLayoutMetrics.spacing
        )
    }

    func canResizeFocusedDeskBoards(toFit count: Int) -> Bool {
        focusedDesk()?.boards.isEmpty == false && boardWidth(toFit: count) != nil
    }

    func showBoardWidthPanel() {
        guard focusedDesk()?.boards.isEmpty == false else { return }
        boardWidthPanelMessage = nil
        setTemporaryContext(.boardWidth)
    }

    func hideBoardWidthPanel() {
        if temporaryContext == .boardWidth { setTemporaryContext(nil) }
    }

    @discardableResult
    func resizeFocusedDeskBoards(toFit count: Int) -> Bool {
        guard let deskID = focusedDesk()?.id, let width = boardWidth(toFit: count) else {
            boardWidthPanelMessage = "\(count) Boards cannot fit at this window width"
            return false
        }
        guard boardActions.resizeDeskBoards(deskID, width) else { return false }
        maximizedBoardID = nil
        hideBoardWidthPanel()
        centerFocusedBoard()
        return true
    }
}
