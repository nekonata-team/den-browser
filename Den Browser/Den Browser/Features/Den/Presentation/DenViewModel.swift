import DenDomain
import Observation
import SwiftUI

@MainActor
@Observable
final class DenViewModel {
    let store: DenStore
    let overview: OverviewViewModel
    let drawer: DrawerViewModel
    let openBoard: OpenBoardViewModel
    let deskFilter: DeskFilterViewModel
    let notificationList: NotificationListViewModel
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
    var zmxSessions = ZmxSessionsModel()
    var pendingConfirmation: DenConfirmationRequest?
    var maximizedBoardID: UUID?
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
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var lastReceivedFeedbackID: UUID?

    init(store: DenStore, feedbackDuration: Duration = .seconds(5)) {
        self.store = store
        overview = OverviewViewModel(store: store)
        drawer = DrawerViewModel(store: store)
        openBoard = OpenBoardViewModel(store: store)
        deskFilter = DeskFilterViewModel(store: store)
        notificationList = NotificationListViewModel(store: store)
        self.feedbackDuration = feedbackDuration
        overview.onDismiss = { [weak self] in self?.hideOverview() }
        drawer.onPreviewExpanded = { [weak self] in self?.isDenMode = false }
        deskFilter.onCenterFocusedBoard = { [weak self] in self?.centerFocusedBoardRequest += 1 }
    }

    deinit {
        feedbackTask?.cancel()
    }

    func connect() {
        store.onWindowEffect = { [weak self] effect in
            self?.receive(effect)
        }
        receive(.feedback(store.latestFeedback))
    }

    func disconnect() {
        store.onWindowEffect = nil
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
            if store.board(for: boardID)?.isTerminal == true, store.focusedBoard?.id != boardID { return }
            store.focusBoard(boardID, exitsDenMode: true)
        case .drawerItemRemoved(let itemID, let previousItems, let advancesPreview, let focusNext):
            drawer.itemWasRemoved(
                itemID,
                previousItems: previousItems,
                advancesPreview: advancesPreview,
                focusNext: focusNext)
            if store.state.drawerItems.isEmpty { closeDrawer() }
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
        store.openFeedbackTarget(feedback.target)
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
