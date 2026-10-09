import DenApplication
import DenDomain
import DenPresentation
import Observation
import SwiftUI

@MainActor
@Observable
final class DenWindowModel {
    let controller: DenController
    let overview: OverviewModel
    let drawer: DrawerModel
    let openBoard: OpenBoardModel
    let deskFilter: DeskFilterModel
    let notificationList: NotificationListModel
    var temporaryContext: TemporaryContext?
    var selectedEssentialID: UUID?
    var saveEssentialDraft: SaveEssentialDraft?
    var isZenViewPresented = false
    var isFocusModePresented = false
    var isDenMode = false
    var isFullscreenActive = false
    var isNotificationListPresented = false
    var boardWidthPanelMessage: String?
    var zmxSessionsReturnToOpenBoard = false
    var zmxDuplicationRootSessionName: String?
    let zmxSessions: ZmxSessionsModel
    var pendingConfirmation: DenConfirmationRequest?
    var maximizedBoardID: BoardID?
    var centerFocusedBoardRequest = 0
    var revealPreviousBoardRequest = 0
    var revealNextBoardRequest = 0
    var boardDragCancellationRequest = 0
    var deskDragCancellationRequest = 0
    var boardLayoutMetrics: BoardLayoutMetrics?
    var pendingBoardLinkFocus: BoardLinkFocusIntent?
    var pendingBoardRemoval: BoardRemovalIntent?
    var boardMutationAnimationSuppressionRequest = 0
    private(set) var displayedFeedback: DenFeedback?

    @ObservationIgnored private let feedbackDuration: Duration
    @ObservationIgnored let onLaunchEssential: (UUID, Double?) -> Void
    @ObservationIgnored let onSaveEssential: (String, String, String) -> Bool
    @ObservationIgnored let onConfirmOperation: (DenConfirmationRequest) -> Bool
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var lastReceivedFeedbackID: UUID?

    init(
        controller: DenController,
        overview: OverviewModel,
        drawer: DrawerModel,
        openBoard: OpenBoardModel,
        deskFilter: DeskFilterModel,
        notificationList: NotificationListModel,
        zmxSessions: ZmxSessionsModel,
        onLaunchEssential: @escaping (UUID, Double?) -> Void,
        onSaveEssential: @escaping (String, String, String) -> Bool,
        onConfirmOperation: @escaping (DenConfirmationRequest) -> Bool,
        feedbackDuration: Duration = .seconds(5)
    ) {
        self.controller = controller
        self.overview = overview
        self.drawer = drawer
        self.openBoard = openBoard
        self.deskFilter = deskFilter
        self.notificationList = notificationList
        self.zmxSessions = zmxSessions
        self.onLaunchEssential = onLaunchEssential
        self.onSaveEssential = onSaveEssential
        self.onConfirmOperation = onConfirmOperation
        self.feedbackDuration = feedbackDuration
    }

    deinit {
        feedbackTask?.cancel()
    }

    func endWindowPresentation() {
        dismissFeedback()
        deskFilter.cancelCentering()
        zmxSessions.stop()
    }

    func receive(_ effect: DenWindowEffect) {
        switch effect {
        case .feedback(let feedback):
            showFeedback(feedback)
        case .presentOpenBoard(let initialURL, let afterBoardID):
            showOpenBoardPanel(initialURL: initialURL, afterBoardID: afterBoardID)
        case .presentOverview(let deskID, let boardID):
            showOverview(deskID: deskID, boardID: boardID)
        case .presentEditBoardLink:
            showEditBoardLinkPanel()
        case .presentEssentialsPrefix:
            showEssentialsPrefix()
        case .presentZmxSessions(let returnsToOpenBoard, let selectedSessionName):
            showZmxSessions(
                selectedSessionName: selectedSessionName,
                returnsToOpenBoard: returnsToOpenBoard)
        case .presentZmxDuplicationPanel(let rootSessionName):
            zmxDuplicationRootSessionName = rootSessionName
            setTemporaryContext(.zmxDuplication)
        case .openBoardResult(let message):
            openBoard.message = message
        case .dismissTemporaryPresentation:
            setTemporaryContext(nil)
            closeNotificationList()
        case .exitDenMode:
            deskFilter.dismiss()
            isDenMode = false
        case .centerFocusedBoard:
            centerFocusedBoardRequest &+= 1
        case .revealPreviousBoard:
            revealPreviousBoardRequest &+= 1
        case .revealNextBoard:
            revealNextBoardRequest &+= 1
        case .requestConfirmation(let request):
            pendingConfirmation = request
        case .openDrawerItem(let itemID):
            focusDrawerItem(itemID)
        case .notificationAdded(let notificationID):
            notificationList.notificationWasAdded(notificationID)
        case .cancelBoardDrag:
            boardDragCancellationRequest &+= 1
        case .cancelDeskDrag:
            deskDragCancellationRequest &+= 1
        case .dismissDeskFilter:
            deskFilter.dismiss()
        case .clearMaximizedBoard:
            maximizedBoardID = nil
        case .runtimeFocusedBoard(let boardID):
            guard !isDenMode, temporaryContext == nil else { return }
            if controller.board(for: boardID)?.isTerminal == true, controller.focusedBoard?.id != boardID { return }
            controller.focusBoard(boardID, exitsDenMode: true)
        case .drawerItemRemoved(let itemID, let previousItems, let advancesPreview, let focusNext):
            drawer.itemWasRemoved(
                itemID,
                previousItems: previousItems,
                advancesPreview: advancesPreview,
                focusNext: focusNext)
            if controller.state.drawerItems.isEmpty { closeDrawer() }
        case .drawerCleared:
            drawer.resetPresentation()
            closeDrawer()
        case .drawerItemKept(let itemID, let opensDrawer, let selectsItem):
            drawer.itemWasKept(itemID, selectsItem: selectsItem)
            if opensDrawer { openDrawer() }
        case .drawerItemRestored(let itemID):
            let wasDenMode = isDenMode
            drawer.itemWasRestored(itemID)
            openDrawer()
            isDenMode = wasDenMode
        case .boardLinkFocusRequested(let intent):
            pendingBoardLinkFocus = intent
        case .boardRemovalRequested(let intent):
            pendingBoardRemoval = intent
        case .clearBoardInputRequests:
            pendingBoardLinkFocus = nil
            pendingBoardRemoval = nil
        case .suppressBoardMutationAnimation:
            boardMutationAnimationSuppressionRequest &+= 1
        case .boardRemoved(let boardID):
            openBoard.invalidateBoard(boardID)
            if maximizedBoardID == boardID { maximizedBoardID = nil }
            if pendingBoardLinkFocus?.boardID == boardID { pendingBoardLinkFocus = nil }
            overview.invalidateBoard(boardID)
        case .deskRemoved(let deskID):
            overview.invalidateDesk(deskID)
        case .overviewBoardRemoved(let boardID, let deskID, let oldIndex):
            overview.removedBoard(boardID: boardID, deskID: deskID, oldIndex: oldIndex)
        case .resetPresentation:
            resetPresentation()
        case .fullscreenChanged(let isFullscreen):
            isFullscreenActive = isFullscreen
        }
    }

    private func showFeedback(_ feedback: DenFeedback?) {
        guard let feedback else {
            dismissFeedback()
            return
        }
        guard feedback.title?.isEmpty == false || !feedback.body.isEmpty,
            feedback.id != lastReceivedFeedbackID
        else { return }

        lastReceivedFeedbackID = feedback.id
        feedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            displayedFeedback = feedback
        }

        let feedbackID = feedback.id
        let duration = feedbackDuration
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.displayedFeedback?.id == feedbackID else { return }
            self?.dismissFeedback(id: feedbackID)
        }
    }

    func handleTap(on feedback: DenFeedback) {
        guard displayedFeedback?.id == feedback.id else { return }
        controller.openFeedbackTarget(feedback.target)
        dismissFeedback(id: feedback.id)
    }

    func consumeBoardLinkFocus(_ intent: BoardLinkFocusIntent) {
        guard pendingBoardLinkFocus == intent else { return }
        pendingBoardLinkFocus = nil
    }

    func consumeBoardRemoval(_ intent: BoardRemovalIntent) {
        guard pendingBoardRemoval == intent else { return }
        pendingBoardRemoval = nil
    }

    func dismissFeedback(id: UUID? = nil) {
        guard id == nil || displayedFeedback?.id == id else { return }
        feedbackTask?.cancel()
        feedbackTask = nil
        withAnimation(.easeIn(duration: 0.15)) {
            displayedFeedback = nil
        }
    }
}
