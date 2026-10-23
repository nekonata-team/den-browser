import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

@MainActor
final class RuntimeWindowConnection {
    weak var runtimes: BoardRuntimeAccess?
    weak var windowResources: DenWindowResources?
    weak var boardNavigation: BoardNavigation?
    weak var boardOpening: BoardOpeningActions?
    weak var boardRemoval: BoardRemovalPresentation?
    weak var drawer: DrawerActions?
    weak var feedback: WindowFeedbackOutput?
    var onWindowEffect: ((DenWindowEffect) -> Void)?
    var onDownloadActivity: ((DownloadActivityEvent) -> Void)?
    var invalidateBoards: ((Set<BoardID>) -> Void)?
    var invalidateDesk: ((DeskID) -> Void)?
    var presentedDeskID: () -> DeskID? = { nil }
    var focusedBoardID: () -> BoardID? = { nil }

    var onDisconnect: () -> Void = {}

    func disconnect() {
        onDisconnect()
        presentedDeskID = { nil }
        focusedBoardID = { nil }
        runtimes = nil
        windowResources = nil
        boardNavigation = nil
        boardOpening = nil
        boardRemoval = nil
        drawer = nil
        feedback = nil
        onWindowEffect = nil
        onDownloadActivity = nil
    }
}
