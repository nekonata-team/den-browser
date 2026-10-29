import DenApplication
import DenDomain
import DenModels
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
    case movePrevious
    case moveNext
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
    case moveBoardToDrawer
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
    case addItem
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
        session: ProfileWindowSession?,
        windowModel: DenWindowModel?,
        openSettings: () -> Void = {}
    ) {
        if action == .application(.openSettings) {
            openSettings()
            return
        }
        guard let session, let windowModel else { return }

        switch action {
        case .application(let action):
            switch action {
            case .showUniversalSearch(let commandsOnly): windowModel.showUniversalSearch(commandsOnly: commandsOnly)
            case .hideUniversalSearch:
                windowModel.hideUniversalSearch()
                session.runtimes.restoreFocusedFirstResponder()
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
                session.context.feedback.publish("No Essential assigned to '\(label)'.", severity: .warning)
            case .launch(let id): windowModel.launchEssential(id: id)
            case .saveFocusedBoardAsEssential: windowModel.saveFocusedBoardAsEssential()
            }
        case .desk(let action):
            switch action {
            case .focusPrevious: session.boardNavigation.focusPreviousDesk()
            case .focusNext: session.boardNavigation.focusNextDesk()
            case .movePrevious:
                if let deskID = windowModel.focusedDesk?.id {
                    windowModel.desks.moveDesk(deskID, by: -1)
                }
            case .moveNext:
                if let deskID = windowModel.focusedDesk?.id {
                    windowModel.desks.moveDesk(deskID, by: 1)
                }
            case .returnToPrevious: session.boardNavigation.returnToPreviousDesk()
            case .focus(let number): session.boardNavigation.focusDesk(number: number)
            case .showNewPanel: windowModel.showNewDeskPanel()
            case .showSavePresetPanel: windowModel.showSaveDeskPresetPanel()
            case .showReplacePanel: windowModel.showReplaceDeskPanel()
            case .showPresetManager: windowModel.showDeskPresetManagement()
            case .showRenamePanel: windowModel.showRenameDeskPanel()
            case .delete: windowModel.desks.deleteFocusedDesk()
            case .adjustBoardWidths(let amount): windowModel.adjustFocusedDeskBoardWidths(by: amount)
            case .resizeBoards(let count): windowModel.resizeFocusedDeskBoards(toFit: count)
            case .reloadSheets: session.boardOpening.reloadFocusedDeskSheets()
            case .enterFilter: windowModel.deskFilter.enter()
            case .dismissFilter: windowModel.deskFilter.dismiss()
            case .confirmFilterQuery: windowModel.deskFilter.confirmQuery()
            case .confirmFilterSelection: windowModel.deskFilter.confirmSelection()
            case .selectFilterBoard(let offset): windowModel.deskFilter.selectBoard(by: offset)
            case .requestDragCancellation: windowModel.requestDeskDragCancellation()
            }
        case .board(let action):
            switch action {
            case .focusPrevious: session.boardNavigation.focusPreviousBoard()
            case .focusNext: session.boardNavigation.focusNextBoard()
            case .moveLeft: session.boardNavigation.moveFocusedBoardLeft()
            case .moveRight: session.boardNavigation.moveFocusedBoardRight()
            case .increaseSheetSize: session.runtimes.adjustFocusedSheetSize(by: 1)
            case .decreaseSheetSize: session.runtimes.adjustFocusedSheetSize(by: -1)
            case .resetSheetSize: session.runtimes.resetFocusedSheetSize()
            case .toggleAnchor: session.boardNavigation.toggleAnchorBoard()
            case .jumpToAnchor: session.boardNavigation.jumpToAnchorBoard()
            case .moveToDesk(let number): session.boardNavigation.moveFocusedBoard(toDeskNumber: number)
            case .showOpenPanel: windowModel.showOpenBoardPanel()
            case .openFromClipboard:
                session.input.openBoardFromClipboard(preferredWidth: windowModel.defaultBoardWidth)
            case .openClipboardInDrawer: session.input.openBoardFromClipboard(inDrawer: true)
            case .showWidthPanel: windowModel.showBoardWidthPanel()
            case .hideWidthPanel: windowModel.hideBoardWidthPanel()
            case .adjustWidth(let amount): windowModel.adjustFocusedBoardWidth(by: amount)
            case .toggleMaximized: windowModel.toggleFocusedBoardMaximized()
            case .center: windowModel.centerFocusedBoard()
            case .revealPrevious: windowModel.revealPreviousBoard()
            case .revealNext: windowModel.revealNextBoard()
            case .toggleSheetNavigationPause: session.boardNavigation.toggleFocusedBoardSheetNavigationPause()
            case .reloadFromOrigin: session.boardOpening.reloadFocusedBoardFromOrigin()
            case .reload: session.boardOpening.reloadFocusedBoard()
            case .goBack: session.boardOpening.goBackInFocusedBoard()
            case .goForward: session.boardOpening.goForwardInFocusedBoard()
            case .goToFirstSheet: session.boardOpening.goToFirstSheetInFocusedBoard()
            case .goToLatestSheet: session.boardOpening.goToLatestSheetInFocusedBoard()
            case .captureSheet: session.screenshots.captureFocusedSheetScreenshot()
            case .copySheetScreenshot: session.screenshots.copyFocusedSheetScreenshot()
            case .copyLocation: session.boardNavigation.copyBoardLocation()
            case .copyID:
                if let boardID = windowModel.focusedBoard?.id {
                    session.boardNavigation.copyBoardID(boardID)
                }
            case .moveBoardToDrawer:
                if let boardID = session.navigation.focusedBoard?.id { session.drawer.moveBoardToDrawer(boardID) }
            case .remove: session.boardRemoval.removeFocusedBoard()
            case .quit: session.zmx.quitFocusedBoard()
            case .removeAndFocusNext: session.boardRemoval.removeFocusedBoard(focusNext: true)
            case .restore: session.boardRemoval.restoreRecentlyRemovedBoard()
            case .showRenamePanel: windowModel.showRenameBoardPanel()
            case .showEditLinkPanel: windowModel.showEditBoardLinkPanel()
            case .duplicate: session.zmx.duplicateFocusedBoard()
            case .duplicateFirstSheet: session.zmx.duplicateFocusedBoardFromFirstSheet()
            case .createTerminalSideBoard:
                if let boardID = windowModel.focusedBoard?.id {
                    session.sideBoards.createTerminalSideBoard(targetBoardID: boardID)
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
            case .addItem: windowModel.drawer.addItem()
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
            case .restoreDiscardedItem: session.drawer.restoreRecentlyDiscardedDrawerItem()
            case .placeSelectedItemAsBoard: windowModel.placeSelectedDrawerItemAsBoard()
            case .requestClearConfirmation: session.drawer.requestDrawerClearConfirmation()
            }
        }
    }
}
