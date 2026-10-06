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
    case increaseSheetSize
    case decreaseSheetSize
    case resetSheetSize
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
        viewModel: DenViewModel?,
        openSettings: () -> Void = {}
    ) {
        if action == .application(.openSettings) {
            openSettings()
            return
        }
        guard let viewModel else { return }
        let store = viewModel.store

        switch action {
        case .application(let action):
            switch action {
            case .openSettings: break
            case .toggleDenMode: viewModel.toggleDenMode()
            case .toggleBoardRail: viewModel.toggleBoardRail()
            case .exitDenMode: viewModel.exitDenMode()
            case .showKeyboardShortcuts: viewModel.showKeyboardShortcuts()
            case .hideKeyboardShortcuts: viewModel.hideKeyboardShortcuts()
            case .toggleZenView: viewModel.toggleZenView()
            case .toggleFocusMode: viewModel.toggleFocusMode()
            }
        case .notifications(let action):
            switch action {
            case .toggle: viewModel.toggleNotificationList()
            case .close: viewModel.closeNotificationList()
            case .moveSelection(let offset): viewModel.notificationList.moveSelection(by: offset)
            case .openSelected: viewModel.notificationList.openSelectedNotification()
            }
        case .essentials(let action):
            switch action {
            case .enterPrefix: viewModel.enterEssentialsPrefix()
            case .exitPrefix: viewModel.exitEssentialsPrefix()
            case .moveSelection(let offset): viewModel.moveEssentialSelection(by: offset)
            case .launchSelected: viewModel.launchSelectedEssential()
            case .showNotFound(let key):
                viewModel.exitEssentialsPrefix()
                let label: String
                switch key {
                case " ": label = "Space"
                case "\r", "\n": label = "Return"
                case "\t": label = "Tab"
                case "\u{8}", "\u{7F}": label = "Delete"
                default: label = key
                }
                store.reportFeedback("No Essential assigned to '\(label)'.", severity: .warning)
            case .launch(let id): viewModel.launchEssential(id: id)
            case .saveFocusedBoardAsEssential: viewModel.saveFocusedBoardAsEssential()
            }
        case .desk(let action):
            switch action {
            case .focusPrevious: store.focusPreviousDesk()
            case .focusNext: store.focusNextDesk()
            case .returnToPrevious: store.returnToPreviousDesk()
            case .focus(let number): store.focusDesk(number: number)
            case .showNewPanel: viewModel.showNewDeskPanel()
            case .showSavePresetPanel: viewModel.showSaveDeskPresetPanel()
            case .showReplacePanel: viewModel.showReplaceDeskPanel()
            case .showPresetManager: viewModel.showDeskPresetManagement()
            case .showRenamePanel: viewModel.showRenameDeskPanel()
            case .delete: store.deleteFocusedDesk()
            case .adjustBoardWidths(let amount): viewModel.adjustFocusedDeskBoardWidths(by: amount)
            case .resizeBoards(let count): viewModel.resizeFocusedDeskBoards(toFit: count)
            case .reloadSheets: store.reloadFocusedDeskSheets()
            case .enterFilter: viewModel.deskFilter.enter()
            case .dismissFilter: viewModel.deskFilter.dismiss()
            case .confirmFilterQuery: viewModel.deskFilter.confirmQuery()
            case .confirmFilterSelection: viewModel.deskFilter.confirmSelection()
            case .selectFilterBoard(let offset): viewModel.deskFilter.selectBoard(by: offset)
            case .requestDragCancellation: viewModel.requestDeskDragCancellation()
            }
        case .board(let action):
            switch action {
            case .focusPrevious: store.focusPreviousBoard()
            case .focusNext: store.focusNextBoard()
            case .moveLeft: store.moveFocusedBoardLeft()
            case .moveRight: store.moveFocusedBoardRight()
            case .increaseSheetSize: store.adjustFocusedSheetSize(by: 1)
            case .decreaseSheetSize: store.adjustFocusedSheetSize(by: -1)
            case .resetSheetSize: store.resetFocusedSheetSize()
            case .toggleAnchor: store.toggleAnchorBoard()
            case .jumpToAnchor: store.jumpToAnchorBoard()
            case .moveToPreviousDesk: store.moveFocusedBoardToPreviousDesk()
            case .moveToNextDesk: store.moveFocusedBoardToNextDesk()
            case .moveToDesk(let number): store.moveFocusedBoard(toDeskNumber: number)
            case .showOpenPanel: viewModel.showOpenBoardPanel()
            case .openFromClipboard: viewModel.openBoardFromClipboard()
            case .showWidthPanel: viewModel.showBoardWidthPanel()
            case .hideWidthPanel: viewModel.hideBoardWidthPanel()
            case .adjustWidth(let amount): viewModel.adjustFocusedBoardWidth(by: amount)
            case .toggleMaximized: viewModel.toggleFocusedBoardMaximized()
            case .center: viewModel.centerFocusedBoard()
            case .revealPrevious: viewModel.revealPreviousBoard()
            case .revealNext: viewModel.revealNextBoard()
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
            case .showRenamePanel: viewModel.showRenameBoardPanel()
            case .showEditLinkPanel: viewModel.showEditBoardLinkPanel()
            case .duplicate: store.duplicateFocusedBoard()
            case .duplicateFirstSheet: store.duplicateFocusedBoardFromFirstSheet()
            case .requestDragCancellation: viewModel.requestBoardDragCancellation()
            }
        case .zmxSessions(let action):
            switch action {
            case .hide: viewModel.hideZmxSessions()
            case .enterFilter: viewModel.enterZmxSessionFilter()
            case .exitFilter: viewModel.exitZmxSessionFilter()
            case .clearFilter: viewModel.clearZmxSessionFilter()
            case .moveSelection(let offset): viewModel.selectZmxSession(by: offset)
            case .toggleSelection: viewModel.toggleZmxSessionSelection()
            case .selectAll: viewModel.selectAllZmxSessions()
            case .clearSelection: viewModel.clearZmxSessionSelection()
            case .openSelected: viewModel.openSelectedZmxSession()
            case .deleteSelected: viewModel.requestZmxSessionDeletion()
            case .refresh: viewModel.refreshZmxSessions()
            }
        case .overview(let action):
            switch action {
            case .show: viewModel.showOverview()
            case .hide: viewModel.hideOverview()
            case .toggleActivity: viewModel.toggleBoardActivity()
            case .hideActivity: viewModel.hideBoardActivity()
            case .enterSelection: viewModel.overview.enterSelection()
            case .enterFilterMode: viewModel.overview.enterFilterMode()
            case .exitFilterMode: viewModel.overview.exitFilterMode()
            case .confirmFilterQuery: viewModel.overview.confirmFilterQuery()
            case .clearQuery: viewModel.overview.clearQuery()
            case .selectPreviousBoard: viewModel.overview.selectPreviousBoard()
            case .selectNextBoard: viewModel.overview.selectNextBoard()
            case .selectPreviousDesk: viewModel.overview.selectPreviousDesk()
            case .selectNextDesk: viewModel.overview.selectNextDesk()
            case .moveSelectionBoardLeft: viewModel.overview.moveSelectionBoardLeft()
            case .moveSelectionBoardRight: viewModel.overview.moveSelectionBoardRight()
            case .moveSelectionBoardToPreviousDesk: viewModel.overview.moveSelectionBoardToPreviousDesk()
            case .moveSelectionBoardToNextDesk: viewModel.overview.moveSelectionBoardToNextDesk()
            }
        case .drawer(let action):
            switch action {
            case .toggle: viewModel.toggleDrawer()
            case .toggleStyle: viewModel.drawer.toggleStyle()
            case .close: viewModel.closeDrawer()
            case .enterFilterMode: viewModel.drawer.enterFilterMode()
            case .exitFilterMode: viewModel.drawer.exitFilterMode()
            case .confirmFilterQuery: viewModel.drawer.confirmFilterQuery()
            case .confirmFilterSelection: viewModel.drawer.confirmFilterSelection()
            case .selectItem(let offset): viewModel.drawer.selectItem(by: offset)
            case .toggleSelectedItem: viewModel.drawer.toggleSelectedItem()
            case .discardSelectedItem(let focusNext):
                viewModel.drawer.discardSelectedItem(focusNext: focusNext)
            case .restoreDiscardedItem: store.restoreRecentlyDiscardedDrawerItem()
            case .placeSelectedItemAsBoard: viewModel.placeSelectedDrawerItemAsBoard()
            case .requestClearConfirmation: store.requestDrawerClearConfirmation()
            }
        }
    }
}
