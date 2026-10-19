import DenApplication
import DenDomain
import DenPresentationModels
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
    case showUniversalSearch(commandsOnly: Bool)
    case hideUniversalSearch
    case moveSearchSelection(Int)
    case submitSearch
    case submitSearchInDrawer
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
    case launchSelectedInDrawer
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
    case quit
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
    case openClipboardInDrawer
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
    case createTerminalSideBoard
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
    case removeSelection(focusNext: Bool)
    case restoreRemovedBoard
    case zoomIn
    case zoomOut
    case resetZoom
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
        controller: DenController?,
        windowModel: DenWindowModel?,
        openSettings: () -> Void = {}
    ) {
        if action == .application(.openSettings) {
            openSettings()
            return
        }
        guard let controller, let windowModel else { return }

        switch action {
        case .application(let action):
            switch action {
            case .showUniversalSearch(let commandsOnly): windowModel.showUniversalSearch(commandsOnly: commandsOnly)
            case .hideUniversalSearch:
                windowModel.hideUniversalSearch()
                controller.restoreFocusedFirstResponder()
            case .moveSearchSelection(let offset): windowModel.universalSearch.moveSelection(by: offset)
            case .submitSearch: windowModel.universalSearch.submit()
            case .submitSearchInDrawer: windowModel.universalSearch.submit(inDrawer: true)
            case .openSettings: break
            case .toggleDenMode: windowModel.toggleDenMode()
            case .toggleBoardRail: windowModel.toggleBoardRail()
            case .exitDenMode: windowModel.exitDenMode()
            case .showKeyboardShortcuts: windowModel.showKeyboardShortcuts()
            case .hideKeyboardShortcuts: windowModel.hideKeyboardShortcuts()
            case .toggleZenView: windowModel.toggleZenView()
            case .toggleFocusMode: windowModel.toggleFocusMode()
            }
        case .notifications(let action):
            switch action {
            case .toggle: windowModel.toggleNotificationList()
            case .close: windowModel.closeNotificationList()
            case .moveSelection(let offset): windowModel.notificationList.moveSelection(by: offset)
            case .openSelected: windowModel.notificationList.openSelectedNotification()
            }
        case .essentials(let action):
            switch action {
            case .enterPrefix: windowModel.enterEssentialsPrefix()
            case .exitPrefix: windowModel.exitEssentialsPrefix()
            case .moveSelection(let offset): windowModel.moveEssentialSelection(by: offset)
            case .launchSelected: windowModel.launchSelectedEssential()
            case .launchSelectedInDrawer: windowModel.launchSelectedEssential(inDrawer: true)
            case .showNotFound(let key):
                windowModel.exitEssentialsPrefix()
                let label: String
                switch key {
                case " ": label = "Space"
                case "\r", "\n": label = "Return"
                case "\t": label = "Tab"
                case "\u{8}", "\u{7F}": label = "Delete"
                default: label = key
                }
                controller.reportFeedback("No Essential assigned to '\(label)'.", severity: .warning)
            case .launch(let id): windowModel.launchEssential(id: id)
            case .saveFocusedBoardAsEssential: windowModel.saveFocusedBoardAsEssential()
            }
        case .desk(let action):
            switch action {
            case .focusPrevious: controller.focusPreviousDesk()
            case .focusNext: controller.focusNextDesk()
            case .returnToPrevious: controller.returnToPreviousDesk()
            case .focus(let number): controller.focusDesk(number: number)
            case .showNewPanel: windowModel.showNewDeskPanel()
            case .showSavePresetPanel: windowModel.showSaveDeskPresetPanel()
            case .showReplacePanel: windowModel.showReplaceDeskPanel()
            case .showPresetManager: windowModel.showDeskPresetManagement()
            case .showRenamePanel: windowModel.showRenameDeskPanel()
            case .delete: controller.deleteFocusedDesk()
            case .adjustBoardWidths(let amount): windowModel.adjustFocusedDeskBoardWidths(by: amount)
            case .resizeBoards(let count): windowModel.resizeFocusedDeskBoards(toFit: count)
            case .reloadSheets: controller.reloadFocusedDeskSheets()
            case .enterFilter: windowModel.deskFilter.enter()
            case .dismissFilter: windowModel.deskFilter.dismiss()
            case .confirmFilterQuery: windowModel.deskFilter.confirmQuery()
            case .confirmFilterSelection: windowModel.deskFilter.confirmSelection()
            case .selectFilterBoard(let offset): windowModel.deskFilter.selectBoard(by: offset)
            case .requestDragCancellation: windowModel.requestDeskDragCancellation()
            }
        case .board(let action):
            switch action {
            case .focusPrevious: controller.focusPreviousBoard()
            case .focusNext: controller.focusNextBoard()
            case .moveLeft: controller.moveFocusedBoardLeft()
            case .moveRight: controller.moveFocusedBoardRight()
            case .increaseSheetSize: controller.adjustFocusedSheetSize(by: 1)
            case .decreaseSheetSize: controller.adjustFocusedSheetSize(by: -1)
            case .resetSheetSize: controller.resetFocusedSheetSize()
            case .toggleAnchor: controller.toggleAnchorBoard()
            case .jumpToAnchor: controller.jumpToAnchorBoard()
            case .moveToPreviousDesk: controller.moveFocusedBoardToPreviousDesk()
            case .moveToNextDesk: controller.moveFocusedBoardToNextDesk()
            case .moveToDesk(let number): controller.moveFocusedBoard(toDeskNumber: number)
            case .showOpenPanel: windowModel.showOpenBoardPanel()
            case .openFromClipboard: controller.openBoardFromClipboard(preferredWidth: windowModel.defaultBoardWidth)
            case .openClipboardInDrawer: controller.openBoardFromClipboard(inDrawer: true)
            case .showWidthPanel: windowModel.showBoardWidthPanel()
            case .hideWidthPanel: windowModel.hideBoardWidthPanel()
            case .adjustWidth(let amount): windowModel.adjustFocusedBoardWidth(by: amount)
            case .toggleMaximized: windowModel.toggleFocusedBoardMaximized()
            case .center: windowModel.centerFocusedBoard()
            case .revealPrevious: windowModel.revealPreviousBoard()
            case .revealNext: windowModel.revealNextBoard()
            case .toggleSheetNavigationPause: controller.toggleFocusedBoardSheetNavigationPause()
            case .reloadFromOrigin: controller.reloadFocusedBoardFromOrigin()
            case .reload: controller.reloadFocusedBoard()
            case .goBack: controller.goBackInFocusedBoard()
            case .goForward: controller.goForwardInFocusedBoard()
            case .goToFirstSheet: controller.goToFirstSheetInFocusedBoard()
            case .goToLatestSheet: controller.goToLatestSheetInFocusedBoard()
            case .captureSheet: controller.captureFocusedSheetScreenshot()
            case .copySheetScreenshot: controller.copyFocusedSheetScreenshot()
            case .copyLocation: controller.copyBoardLocation()
            case .copyID:
                if let boardID = controller.focusedBoard?.id {
                    controller.copyBoardID(boardID)
                }
            case .keepSheetInDrawer: controller.keepFocusedSheetInDrawer()
            case .remove: controller.removeFocusedBoard()
            case .quit: controller.quitFocusedBoard()
            case .removeAndFocusNext: controller.removeFocusedBoard(focusNext: true)
            case .restore: controller.restoreRecentlyRemovedBoard()
            case .showRenamePanel: windowModel.showRenameBoardPanel()
            case .showEditLinkPanel: windowModel.showEditBoardLinkPanel()
            case .duplicate: controller.duplicateFocusedBoard()
            case .duplicateFirstSheet: controller.duplicateFocusedBoardFromFirstSheet()
            case .createTerminalSideBoard:
                if let boardID = controller.focusedBoard?.id {
                    controller.createTerminalSideBoard(targetBoardID: boardID)
                }
            case .requestDragCancellation: windowModel.requestBoardDragCancellation()
            }
        case .zmxSessions(let action):
            switch action {
            case .hide: windowModel.hideZmxSessions()
            case .enterFilter: windowModel.enterZmxSessionFilter()
            case .exitFilter: windowModel.exitZmxSessionFilter()
            case .clearFilter: windowModel.clearZmxSessionFilter()
            case .moveSelection(let offset): windowModel.selectZmxSession(by: offset)
            case .toggleSelection: windowModel.toggleZmxSessionSelection()
            case .selectAll: windowModel.selectAllZmxSessions()
            case .clearSelection: windowModel.clearZmxSessionSelection()
            case .openSelected: windowModel.openSelectedZmxSession()
            case .deleteSelected: windowModel.requestZmxSessionDeletion()
            case .refresh: windowModel.refreshZmxSessions()
            }
        case .overview(let action):
            switch action {
            case .removeSelection(let focusNext): windowModel.overview.removeSelectedBoard(focusNext: focusNext)
            case .restoreRemovedBoard: windowModel.overview.restoreRemovedBoard()
            case .zoomIn: windowModel.overview.adjustCanvasZoom(by: 1)
            case .zoomOut: windowModel.overview.adjustCanvasZoom(by: -1)
            case .resetZoom: windowModel.overview.resetCanvasZoom()
            case .show: windowModel.showOverview()
            case .hide: windowModel.hideOverview()
            case .toggleActivity: windowModel.toggleBoardActivity()
            case .hideActivity: windowModel.hideBoardActivity()
            case .enterSelection: windowModel.overview.enterSelection()
            case .enterFilterMode: windowModel.overview.enterFilterMode()
            case .exitFilterMode: windowModel.overview.exitFilterMode()
            case .confirmFilterQuery: windowModel.overview.confirmFilterQuery()
            case .clearQuery: windowModel.overview.clearQuery()
            case .selectPreviousBoard: windowModel.overview.selectPreviousBoard()
            case .selectNextBoard: windowModel.overview.selectNextBoard()
            case .selectPreviousDesk: windowModel.overview.selectPreviousDesk()
            case .selectNextDesk: windowModel.overview.selectNextDesk()
            case .moveSelectionBoardLeft: windowModel.overview.moveSelectionBoardLeft()
            case .moveSelectionBoardRight: windowModel.overview.moveSelectionBoardRight()
            case .moveSelectionBoardToPreviousDesk: windowModel.overview.moveSelectionBoardToPreviousDesk()
            case .moveSelectionBoardToNextDesk: windowModel.overview.moveSelectionBoardToNextDesk()
            }
        case .drawer(let action):
            switch action {
            case .toggle: windowModel.toggleDrawer()
            case .toggleStyle: windowModel.drawer.toggleStyle()
            case .close: windowModel.closeDrawer()
            case .enterFilterMode: windowModel.drawer.enterFilterMode()
            case .exitFilterMode: windowModel.drawer.exitFilterMode()
            case .confirmFilterQuery: windowModel.drawer.confirmFilterQuery()
            case .confirmFilterSelection: windowModel.drawer.confirmFilterSelection()
            case .selectItem(let offset): windowModel.drawer.selectItem(by: offset)
            case .toggleSelectedItem: windowModel.drawer.toggleSelectedItem()
            case .discardSelectedItem(let focusNext):
                windowModel.drawer.discardSelectedItem(focusNext: focusNext)
            case .restoreDiscardedItem: controller.restoreRecentlyDiscardedDrawerItem()
            case .placeSelectedItemAsBoard: windowModel.placeSelectedDrawerItemAsBoard()
            case .requestClearConfirmation: controller.requestDrawerClearConfirmation()
            }
        }
    }
}
