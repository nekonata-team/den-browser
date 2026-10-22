import DenApplication
import DenDomain

extension DenController {
    func adjustBoardWidth(_ boardID: BoardID, by delta: Double) {
        storage.boardSizing.adjustBoard(boardID, by: delta)
    }

    func adjustDeskBoardWidths(_ deskID: DeskID, by delta: Double) {
        storage.boardSizing.adjustDesk(deskID, by: delta)
    }

    @discardableResult
    func resizeDeskBoards(_ deskID: DeskID, to width: Double) -> Bool {
        storage.boardSizing.resizeDesk(deskID, to: width)
    }

    func resizeBoard(_ boardID: BoardID, to width: Double) {
        storage.boardSizing.resizeBoard(boardID, to: width)
    }

    func resizeBoardPair(_ boardID: BoardID, to width: Double) {
        storage.boardSizing.resizePair(boardID, to: width)
    }

    func saveBoardWidths() {
        storage.boardSizing.saveWidths()
    }
}
