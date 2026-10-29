import DenApplication
import DenDomain
import DenModels

extension BoardSurfaceModel {
    init(board: BoardState, session: ProfileWindowSession) {
        self.init(
            desks: { [state = session.resources.data] in state.snapshot.den.desks },
            boardDeskID: { [state = session.resources.data] in
                state.snapshot.den.desks.first { $0.boards.contains { $0.id == board.id } }?.id
            },
            canMoveLeft: { [movement = session.resources.boardMovement] in movement.canMove(board.id, by: -1) },
            canMoveRight: { [movement = session.resources.boardMovement] in movement.canMove(board.id, by: 1) },
            inputSourceLabel: { [weak session] in
                guard let session, session.configuration.preferences.rememberBoardInputMethod else { return nil }
                return session.inputSourceTracker.shortLabel(for: board.id)
            },
            sheetNavigationEnabled: { [weak session] in session?.configuration.sheetNavigation.isEnabled ?? false },
            drawerStyle: { [preferences = session.configuration.preferences] in preferences.drawerStyle },
            motionPreference: { [preferences = session.configuration.preferences] in preferences.motionPreference },
            perform: { [weak session] action in
                guard let session else { return }
                switch action {
                case .focus: session.boardNavigation.focusBoard(board.id)
                case .duplicate: session.zmx.duplicateFocusedBoard()
                case .moveLeft: session.boardNavigation.moveFocusedBoardLeft()
                case .moveRight: session.boardNavigation.moveFocusedBoardRight()
                case .remove: session.boardRemoval.removeBoard(board.id)
                case .copyID: session.boardNavigation.copyBoardID(board.id)
                case .copyLocation: session.boardNavigation.copyBoardLocation(board.id)
                case .inspect: session.sideBoards.createInspectionBoard(targetBoardID: board.id)
                case .moveToDrawer: session.drawer.moveBoardToDrawer(board.id)
                case .goToFirst: session.boardOpening.goToFirstSheetInFocusedBoard()
                case .toggleNavigation: session.boardNavigation.toggleBoardSheetNavigationPause(board.id)
                case .screenshot: session.screenshots.captureFocusedSheetScreenshot()
                case .increaseSize: session.runtimes.adjustFocusedSheetSize(by: 1)
                case .decreaseSize: session.runtimes.adjustFocusedSheetSize(by: -1)
                case .resetSize: session.runtimes.resetFocusedSheetSize()
                case .moveToDesk(let number): session.boardNavigation.moveFocusedBoard(toDeskNumber: number)
                }
            })
    }
}
