public import DenApplication
import DenDomain
import Foundation
import Observation

@MainActor
@Observable
public final class DenWindowModel {
    public struct Inputs {
        public let essentials: () -> [Essential]
        public let isBoardRailPresented: () -> Bool
        public let isBoardDragging: () -> Bool
        public let isDeskDragging: () -> Bool

        public init(
            essentials: @escaping () -> [Essential],
            isBoardRailPresented: @escaping () -> Bool,
            isBoardDragging: @escaping () -> Bool,
            isDeskDragging: @escaping () -> Bool
        ) {
            self.essentials = essentials
            self.isBoardRailPresented = isBoardRailPresented
            self.isBoardDragging = isBoardDragging
            self.isDeskDragging = isDeskDragging
        }
    }

    public struct WindowActions {
        public let setBoardRailPresented: (Bool) -> Void
        public let openFeedbackTarget: (DenFeedback.Target?) -> Void
        public let reportWarning: (String) -> Void
        public let didEnterDenMode: () -> Void
        public let didShowKeyboardShortcuts: () -> Void

        public init(
            setBoardRailPresented: @escaping (Bool) -> Void,
            openFeedbackTarget: @escaping (DenFeedback.Target?) -> Void,
            reportWarning: @escaping (String) -> Void,
            didEnterDenMode: @escaping () -> Void,
            didShowKeyboardShortcuts: @escaping () -> Void
        ) {
            self.setBoardRailPresented = setBoardRailPresented
            self.openFeedbackTarget = openFeedbackTarget
            self.reportWarning = reportWarning
            self.didEnterDenMode = didEnterDenMode
            self.didShowKeyboardShortcuts = didShowKeyboardShortcuts
        }
    }

    public struct BoardActions {
        public let placeDrawerItem: (UUID, Double?) -> BoardID?
        public let focusBoard: (BoardID, Bool) -> Void
        public let centerFocusedBoard: () -> Void
        public let cancelBoardDrag: () -> Void
        public let cancelDeskDrag: () -> Void

        public init(
            placeDrawerItem: @escaping (UUID, Double?) -> BoardID?,
            focusBoard: @escaping (BoardID, Bool) -> Void,
            centerFocusedBoard: @escaping () -> Void,
            cancelBoardDrag: @escaping () -> Void,
            cancelDeskDrag: @escaping () -> Void
        ) {
            self.placeDrawerItem = placeDrawerItem
            self.focusBoard = focusBoard
            self.centerFocusedBoard = centerFocusedBoard
            self.cancelBoardDrag = cancelBoardDrag
            self.cancelDeskDrag = cancelDeskDrag
        }
    }

    public struct ZmxActions {
        public let canPresentSessions: () -> Bool
        public let openSession: (String, Double?, Bool) -> ZmxSessionOpenResult
        public let boardLocation: (String) -> String?
        public let cancelDuplication: () -> Void

        public init(
            canPresentSessions: @escaping () -> Bool,
            openSession: @escaping (String, Double?, Bool) -> ZmxSessionOpenResult,
            boardLocation: @escaping (String) -> String?,
            cancelDuplication: @escaping () -> Void
        ) {
            self.canPresentSessions = canPresentSessions
            self.openSession = openSession
            self.boardLocation = boardLocation
            self.cancelDuplication = cancelDuplication
        }
    }

    public let boardEditing: BoardEditingModel
    public let downloads: DownloadActivityModel
    public let desks: DeskListModel
    public var navigation: WindowNavigationModel { desks.navigation }
    public let overview: OverviewModel
    public let drawer: DrawerModel
    public let openBoard: OpenBoardModel
    public let universalSearch = UniversalSearchModel()
    public let deskFilter: DeskFilterModel
    public let notificationList: NotificationListModel
    public var temporaryContext: TemporaryContext?
    public var selectedEssentialID: UUID?
    public var saveEssentialDraft: SaveEssentialDraft?
    public var isZenViewPresented = false
    public var isFocusModePresented = false
    public var isDenMode = false
    public var isFullscreenActive = false
    public var isNotificationListPresented = false
    public var boardWidthPanelMessage: String?
    public var zmxSessionsReturnToOpenBoard = false
    public var zmxDuplicationRootSessionName: String?
    public let zmxSessions: ZmxSessionsModel
    public var pendingConfirmation: DenConfirmationRequest?
    public var maximizedBoardID: BoardID?
    public var centerFocusedBoardRequest = 0
    public var revealPreviousBoardRequest = 0
    public var revealNextBoardRequest = 0
    public var boardDragCancellationRequest = 0
    public var deskDragCancellationRequest = 0
    public var boardLayoutMetrics: BoardLayoutMetrics?
    public var pendingBoardLinkFocus: BoardLinkFocusIntent?
    public var pendingBoardRemoval: BoardRemovalIntent?
    public var boardMutationAnimationSuppressionRequest = 0
    public private(set) var displayedFeedback: DenFeedback?

    @ObservationIgnored private let feedbackDuration: Duration
    @ObservationIgnored let onLaunchEssential: (UUID, Double?, Bool) -> Void
    @ObservationIgnored let onSaveEssential: (String, String, String) -> Bool
    @ObservationIgnored let onConfirmOperation: (DenConfirmationRequest) -> Bool
    @ObservationIgnored let inputs: Inputs
    @ObservationIgnored let windowActions: WindowActions
    @ObservationIgnored let boardSizing: BoardSizing
    @ObservationIgnored let boardActions: BoardActions
    @ObservationIgnored public let deskPresetActions: DeskPresetActions
    @ObservationIgnored let zmxActions: ZmxActions
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var lastReceivedFeedbackID: UUID?

    public init(
        boardEditing: BoardEditingModel,
        desks: DeskListModel,
        downloads: DownloadActivityModel,
        overview: OverviewModel,
        drawer: DrawerModel,
        openBoard: OpenBoardModel,
        deskFilter: DeskFilterModel,
        notificationList: NotificationListModel,
        zmxSessions: ZmxSessionsModel,
        onLaunchEssential: @escaping (UUID, Double?, Bool) -> Void,
        onSaveEssential: @escaping (String, String, String) -> Bool,
        onConfirmOperation: @escaping (DenConfirmationRequest) -> Bool,
        inputs: Inputs,
        windowActions: WindowActions,
        boardSizing: BoardSizing,
        boardActions: BoardActions,
        zmxActions: ZmxActions,
        deskPresetActions: DeskPresetActions,
        feedbackDuration: Duration = .seconds(5)
    ) {
        self.boardEditing = boardEditing
        self.desks = desks
        self.downloads = downloads
        self.overview = overview
        self.drawer = drawer
        self.openBoard = openBoard
        self.deskFilter = deskFilter
        self.notificationList = notificationList
        self.zmxSessions = zmxSessions
        self.onLaunchEssential = onLaunchEssential
        self.onSaveEssential = onSaveEssential
        self.onConfirmOperation = onConfirmOperation
        self.inputs = inputs
        self.windowActions = windowActions
        self.boardSizing = boardSizing
        self.boardActions = boardActions
        self.zmxActions = zmxActions
        self.deskPresetActions = deskPresetActions
        self.feedbackDuration = feedbackDuration
    }

    deinit {
        feedbackTask?.cancel()
    }

    public func endWindowPresentation() {
        dismissFeedback()
        deskFilter.cancelCentering()
        zmxSessions.stop()
    }

    public func receive(_ effect: DenWindowEffect) {
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
        case .drawerPeekMoved(let itemID):
            if drawer.expandedItemID == itemID { drawer.expandedItemID = nil }
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
            if navigation.board(for: boardID)?.isTerminal == true, navigation.focusedBoard?.id != boardID { return }
            boardActions.focusBoard(boardID, true)
        case .drawerItemRemoved(let itemID, let previousItems, let advancesPeek, let focusNext):
            drawer.itemWasRemoved(
                itemID,
                previousItems: previousItems,
                advancesPeek: advancesPeek,
                focusNext: focusNext)
            if drawer.items.isEmpty { closeDrawer() }
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
        displayedFeedback = feedback

        let feedbackID = feedback.id
        let duration = feedbackDuration
        feedbackTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.displayedFeedback?.id == feedbackID else { return }
            self?.dismissFeedback(id: feedbackID)
        }
    }

    public func handleTap(on feedback: DenFeedback) {
        guard displayedFeedback?.id == feedback.id else { return }
        windowActions.openFeedbackTarget(feedback.target)
        dismissFeedback(id: feedback.id)
    }

    public func consumeBoardLinkFocus(_ intent: BoardLinkFocusIntent) {
        guard pendingBoardLinkFocus == intent else { return }
        pendingBoardLinkFocus = nil
    }

    public func consumeBoardRemoval(_ intent: BoardRemovalIntent) {
        guard pendingBoardRemoval == intent else { return }
        pendingBoardRemoval = nil
    }

    public func dismissFeedback(id: UUID? = nil) {
        guard id == nil || displayedFeedback?.id == id else { return }
        feedbackTask?.cancel()
        feedbackTask = nil
        displayedFeedback = nil
    }
}
