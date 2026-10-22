import DenDomain
import DenPresentationModels

extension DenController {
    func boardSurfaceModel(for board: BoardState) -> BoardSurfaceModel {
        BoardSurfaceModel(
            desks: { [weak self] in self?.state.desks ?? [] },
            boardDeskID: { [weak self] in self?.state.desks.first { $0.boards.contains { $0.id == board.id } }?.id },
            canMoveLeft: { [weak self] in self?.canMoveBoard(board.id, by: -1) ?? false },
            canMoveRight: { [weak self] in self?.canMoveBoard(board.id, by: 1) ?? false },
            inputSourceLabel: { [weak self] in
                guard let self, self.preferences.rememberBoardInputMethod else { return nil }
                return self.inputSourceTracker.shortLabel(for: board.id)
            },
            sheetNavigationEnabled: { [weak self] in self?.sheetNavigation.isEnabled ?? false },
            drawerStyle: { [preferences] in preferences.drawerStyle },
            motionPreference: { [preferences] in preferences.motionPreference },
            perform: { [weak self] action in
                guard let self else { return }
                switch action {
                case .focus: self.focusBoard(board.id)
                case .duplicate: self.duplicateFocusedBoard()
                case .moveLeft: self.moveFocusedBoardLeft()
                case .moveRight: self.moveFocusedBoardRight()
                case .remove: self.removeBoard(board.id)
                case .copyID: self.copyBoardID(board.id)
                case .copyLocation: self.copyBoardLocation(board.id)
                case .inspect: self.createInspectionBoard(targetBoardID: board.id)
                case .keepInDrawer: self.keepFocusedSheetInDrawer()
                case .goToFirst: self.goToFirstSheetInFocusedBoard()
                case .toggleNavigation: self.toggleBoardSheetNavigationPause(board.id)
                case .screenshot: self.captureFocusedSheetScreenshot()
                case .increaseSize: self.adjustFocusedSheetSize(by: 1)
                case .decreaseSize: self.adjustFocusedSheetSize(by: -1)
                case .resetSize: self.resetFocusedSheetSize()
                case .moveToDesk(let number): self.moveFocusedBoard(toDeskNumber: number)
                }
            })
    }
}
