import Foundation

enum AppAction: Equatable {
    case application(ApplicationAction)
    case notifications(NotificationsAction)
    case essentials(EssentialsAction)
    case desk(DeskAction)
    case board(BoardAction)
    case zmxSessions(ZmxSessionsAction)
    case overview(OverviewAction)
    case drawer(DrawerAction)
}

enum ApplicationAction: Equatable {
    case openSettings
    case toggleDenMode
    case toggleBoardRail
    case exitDenMode
    case showKeyboardShortcuts
    case hideKeyboardShortcuts
    case toggleZenView
    case toggleFocusMode
}

enum NotificationsAction: Equatable {
    case toggle
    case close
    case moveSelection(Int)
    case openSelected
}

enum EssentialsAction: Equatable {
    case enterPrefix
    case exitPrefix
    case moveSelection(Int)
    case launchSelected
    case showNotFound(String)
    case launch(UUID)
    case saveFocusedBoardAsEssential
}

enum DeskAction: Equatable {
    case focusPrevious
    case focusNext
    case returnToPrevious
    case focus(Int)
    case showNewPanel
    case showSavePresetPanel
    case showReplacePanel
    case showPresetManager
    case showRenamePanel
    case delete
    case adjustBoardWidths(Double)
    case resizeBoards(Int)
    case reloadSheets
    case enterFilter
    case dismissFilter
    case confirmFilterQuery
    case confirmFilterSelection
    case selectFilterBoard(Int)
    case requestDragCancellation
}

enum BoardAction: Equatable {
    case focusPrevious
    case focusNext
    case moveLeft
    case moveRight
    case increaseContentSize
    case decreaseContentSize
    case resetContentSize
    case toggleAnchor
    case jumpToAnchor
    case moveToPreviousDesk
    case moveToNextDesk
    case moveToDesk(Int)
    case showOpenPanel
    case openFromClipboard
    case showWidthPanel
    case hideWidthPanel
    case adjustWidth(Double)
    case toggleMaximized
    case center
    case revealPrevious
    case revealNext
    case toggleSheetNavigationPause
    case reloadFromOrigin
    case reload
    case goBack
    case goForward
    case goToFirstSheet
    case goToLatestSheet
    case captureSheet
    case copySheetScreenshot
    case copyLocation
    case copyID
    case keepSheetInDrawer
    case remove
    case removeAndFocusNext
    case restore
    case showRenamePanel
    case showEditLinkPanel
    case duplicate
    case duplicateFirstSheet
    case requestDragCancellation
}

enum ZmxSessionsAction: Equatable {
    case hide
    case enterFilter
    case exitFilter
    case clearFilter
    case moveSelection(Int)
    case toggleSelection
    case selectAll
    case clearSelection
    case openSelected
    case deleteSelected
    case refresh
}

enum OverviewAction: Equatable {
    case show
    case hide
    case toggleActivity
    case hideActivity
    case enterSelection
    case enterFilterMode
    case exitFilterMode
    case confirmFilterQuery
    case clearQuery
    case selectPreviousBoard
    case selectNextBoard
    case selectPreviousDesk
    case selectNextDesk
    case moveSelectionBoardLeft
    case moveSelectionBoardRight
    case moveSelectionBoardToPreviousDesk
    case moveSelectionBoardToNextDesk
}

enum DrawerAction: Equatable {
    case toggle
    case toggleStyle
    case close
    case enterFilterMode
    case exitFilterMode
    case confirmFilterQuery
    case confirmFilterSelection
    case selectItem(Int)
    case toggleSelectedItem
    case discardSelectedItem(focusNext: Bool)
    case restoreDiscardedItem
    case placeSelectedItemAsBoard
    case requestClearConfirmation
}

@MainActor
enum AppActionHandler {
    static func perform(
        _ action: AppAction,
        store: DenStore?,
        openSettings: () -> Void = {}
    ) {
        if action == .application(.openSettings) {
            openSettings()
            return
        }
        guard let store else { return }

        switch action {
        case .application(let action):
            switch action {
            case .openSettings: break
            case .toggleDenMode: store.toggleDenMode()
            case .toggleBoardRail: store.toggleBoardRail()
            case .exitDenMode: store.exitDenMode()
            case .showKeyboardShortcuts: store.showKeyboardShortcuts()
            case .hideKeyboardShortcuts: store.hideKeyboardShortcuts()
            case .toggleZenView: store.toggleZenView()
            case .toggleFocusMode: store.toggleFocusMode()
            }
        case .notifications(let action):
            switch action {
            case .toggle: store.toggleNotificationList()
            case .close: store.closeNotificationList()
            case .moveSelection(let offset): store.moveNotificationSelection(by: offset)
            case .openSelected: store.openSelectedNotification()
            }
        case .essentials(let action):
            switch action {
            case .enterPrefix: store.enterEssentialsPrefix()
            case .exitPrefix: store.exitEssentialsPrefix()
            case .moveSelection(let offset): store.moveEssentialSelection(by: offset)
            case .launchSelected: store.launchSelectedEssential()
            case .showNotFound(let key):
                store.exitEssentialsPrefix()
                let label: String
                switch key {
                case " ": label = "Space"
                case "\r", "\n": label = "Return"
                case "\t": label = "Tab"
                case "\u{8}", "\u{7F}": label = "Delete"
                default: label = key
                }
                store.showToast("No Essential assigned to '\(label)'.", style: .warning)
            case .launch(let id): store.launchEssential(id: id)
            case .saveFocusedBoardAsEssential: store.saveFocusedBoardAsEssential()
            }
        case .desk(let action):
            switch action {
            case .focusPrevious: store.focusPreviousDesk()
            case .focusNext: store.focusNextDesk()
            case .returnToPrevious: store.returnToPreviousDesk()
            case .focus(let number): store.focusDesk(number: number)
            case .showNewPanel: store.showNewDeskPanel()
            case .showSavePresetPanel: store.showSaveDeskPresetPanel()
            case .showReplacePanel: store.showReplaceDeskPanel()
            case .showPresetManager: store.showDeskPresetManagement()
            case .showRenamePanel: store.showRenameDeskPanel()
            case .delete: store.deleteFocusedDesk()
            case .adjustBoardWidths(let amount): store.adjustFocusedDeskBoardWidths(by: amount)
            case .resizeBoards(let count): store.resizeFocusedDeskBoards(toFit: count)
            case .reloadSheets: store.reloadFocusedDeskSheets()
            case .enterFilter: store.enterDeskFilter()
            case .dismissFilter: store.dismissDeskFilter()
            case .confirmFilterQuery: store.confirmDeskFilterQuery()
            case .confirmFilterSelection: store.confirmDeskFilterSelection()
            case .selectFilterBoard(let offset): store.selectDeskFilterBoard(by: offset)
            case .requestDragCancellation: store.requestDeskDragCancellation()
            }
        case .board(let action):
            switch action {
            case .focusPrevious: store.focusPreviousBoard()
            case .focusNext: store.focusNextBoard()
            case .moveLeft: store.moveFocusedBoardLeft()
            case .moveRight: store.moveFocusedBoardRight()
            case .increaseContentSize: store.adjustFocusedBoardContentSize(by: 1)
            case .decreaseContentSize: store.adjustFocusedBoardContentSize(by: -1)
            case .resetContentSize: store.resetFocusedBoardContentSize()
            case .toggleAnchor: store.toggleAnchorBoard()
            case .jumpToAnchor: store.jumpToAnchorBoard()
            case .moveToPreviousDesk: store.moveFocusedBoardToPreviousDesk()
            case .moveToNextDesk: store.moveFocusedBoardToNextDesk()
            case .moveToDesk(let number): store.moveFocusedBoard(toDeskNumber: number)
            case .showOpenPanel: store.showOpenBoardPanel()
            case .openFromClipboard: store.openBoardFromClipboard()
            case .showWidthPanel: store.showBoardWidthPanel()
            case .hideWidthPanel: store.hideBoardWidthPanel()
            case .adjustWidth(let amount): store.adjustFocusedBoardWidth(by: amount)
            case .toggleMaximized: store.toggleFocusedBoardMaximized()
            case .center: store.centerFocusedBoard()
            case .revealPrevious: store.revealPreviousBoard()
            case .revealNext: store.revealNextBoard()
            case .toggleSheetNavigationPause: store.toggleFocusedBoardSheetNavigationPause()
            case .reloadFromOrigin: store.reloadFocusedBoardFromOrigin()
            case .reload: store.reloadFocusedBoard()
            case .goBack: store.goBackInFocusedBoard()
            case .goForward: store.goForwardInFocusedBoard()
            case .goToFirstSheet: store.goToFirstSheetInFocusedBoard()
            case .goToLatestSheet: store.goToLatestSheetInFocusedBoard()
            case .captureSheet: store.captureFocusedSheetScreenshot()
            case .copySheetScreenshot: store.copyFocusedSheetScreenshot()
            case .copyLocation: store.copyBoardLocation()
            case .copyID:
                if let boardID = store.focusedBoard?.id {
                    store.copyBoardID(boardID)
                }
            case .keepSheetInDrawer: store.keepFocusedSheetInDrawer()
            case .remove: store.removeFocusedBoard()
            case .removeAndFocusNext: store.removeFocusedBoard(focusNext: true)
            case .restore: store.restoreRecentlyRemovedBoard()
            case .showRenamePanel: store.showRenameBoardPanel()
            case .showEditLinkPanel: store.showEditBoardLinkPanel()
            case .duplicate: store.duplicateFocusedBoard()
            case .duplicateFirstSheet: store.duplicateFocusedBoardFromFirstSheet()
            case .requestDragCancellation: store.requestBoardDragCancellation()
            }
        case .zmxSessions(let action):
            switch action {
            case .hide: store.hideZmxSessions()
            case .enterFilter: store.enterZmxSessionFilter()
            case .exitFilter: store.exitZmxSessionFilter()
            case .clearFilter: store.clearZmxSessionFilter()
            case .moveSelection(let offset): store.selectZmxSession(by: offset)
            case .toggleSelection: store.toggleZmxSessionSelection()
            case .selectAll: store.selectAllZmxSessions()
            case .clearSelection: store.clearZmxSessionSelection()
            case .openSelected: store.openSelectedZmxSession()
            case .deleteSelected: store.requestZmxSessionDeletion()
            case .refresh: store.refreshZmxSessions()
            }
        case .overview(let action):
            switch action {
            case .show: store.showOverview()
            case .hide: store.hideOverview()
            case .toggleActivity: store.toggleBoardActivity()
            case .hideActivity: store.hideBoardActivity()
            case .enterSelection: store.enterOverviewSelection()
            case .enterFilterMode: store.enterOverviewFilterMode()
            case .exitFilterMode: store.exitOverviewFilterMode()
            case .confirmFilterQuery: store.confirmOverviewFilterQuery()
            case .clearQuery: store.clearOverviewQuery()
            case .selectPreviousBoard: store.selectPreviousBoardInOverview()
            case .selectNextBoard: store.selectNextBoardInOverview()
            case .selectPreviousDesk: store.selectPreviousDeskInOverview()
            case .selectNextDesk: store.selectNextDeskInOverview()
            case .moveSelectionBoardLeft: store.moveOverviewSelectionBoardLeft()
            case .moveSelectionBoardRight: store.moveOverviewSelectionBoardRight()
            case .moveSelectionBoardToPreviousDesk: store.moveOverviewSelectionBoardToPreviousDesk()
            case .moveSelectionBoardToNextDesk: store.moveOverviewSelectionBoardToNextDesk()
            }
        case .drawer(let action):
            switch action {
            case .toggle: store.toggleDrawer()
            case .toggleStyle: store.toggleDrawerStyle()
            case .close: store.closeDrawer()
            case .enterFilterMode: store.enterDrawerFilterMode()
            case .exitFilterMode: store.exitDrawerFilterMode()
            case .confirmFilterQuery: store.confirmDrawerFilterQuery()
            case .confirmFilterSelection: store.confirmDrawerFilterSelection()
            case .selectItem(let offset): store.selectDrawerItem(by: offset)
            case .toggleSelectedItem: store.toggleSelectedDrawerItem()
            case .discardSelectedItem(let focusNext):
                store.discardSelectedDrawerItem(focusNext: focusNext)
            case .restoreDiscardedItem: store.restoreRecentlyDiscardedDrawerItem()
            case .placeSelectedItemAsBoard: store.placeSelectedDrawerItemAsBoard()
            case .requestClearConfirmation: store.requestDrawerClearConfirmation()
            }
        }
    }
}

extension DenStore {
    func performAppAction(_ action: AppAction, openSettings: () -> Void = {}) {
        AppActionHandler.perform(action, store: self, openSettings: openSettings)
    }
}
