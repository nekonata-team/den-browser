import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import WebKit

@MainActor
final class BoardOpeningActions {
    private let context: WindowNativeContext
    private let boardNavigation: BoardNavigation
    private var runtimes: BoardRuntimeAccess { context.runtimes }
    private var storage: DenProfileResources { context.storage }
    private var state: DenState { context.storage.state }
    private var preferences: AppPreferences { context.configuration.preferences }
    private var focusedDesk: DeskState? { context.focusedDesk }
    private var focusedBoard: BoardState? { context.focusedBoard }
    private var presentedDeskID: DeskID { context.navigation.presentedDeskID }
    private var zmxClient: ZmxClient { context.zmxClient }
    private var zellijClient: ZellijClient { context.zellijClient }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }
    private var drawerPeekRuntime: WebRuntime? {
        get { context.windowResources.drawerPeek }
        set { context.windowResources.drawerPeek = newValue }
    }
    private var webRuntimes: [BoardID: WebRuntime] {
        get { context.storage.webRuntimes }
        set { context.storage.webRuntimes = newValue }
    }

    init(context: WindowNativeContext, boardNavigation: BoardNavigation) {
        self.context = context
        self.boardNavigation = boardNavigation
    }

    func boardCreationTarget(
        afterBoardID: BoardID? = nil, focus: Bool = true,
        origin: BoardOperationOrigin = .interactive, deskID: DeskID? = nil
    ) -> BoardCreation.Target {
        BoardCreation.Target(
            presentedDeskID: presentedDeskID, deskID: deskID, afterBoardID: afterBoardID,
            focus: focus, origin: origin)
    }

    func boardOpeningRequest(
        input: String, preferredWidth: Double?, afterBoardID: BoardID?, zmxRootSessionName: String? = nil
    ) -> BoardCreation.OpenRequest {
        BoardCreation.OpenRequest(
            input: input, width: preferredWidth ?? inheritedBoardWidth,
            target: boardCreationTarget(afterBoardID: afterBoardID),
            configuration: boardOpeningConfiguration,
            zmxRootSessionName: zmxRootSessionName)
    }

    var boardOpeningConfiguration: BoardOpening.Configuration {
        .init(
            searchEngine: preferences.searchEngine, zmxConfigured: zmxClient.isConfigured,
            zellijConfigured: zellijClient.isConfigured, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    func boardCreationNotifications(
        returnsToOpenBoard: Bool = false, existingRuntime: WebRuntime? = nil
    ) -> (BoardCreation.Notice) -> Void {
        { [self] notice in
            switch notice {
            case .willInsert(let board):
                if let existingRuntime {
                    if drawerPeekRuntime === existingRuntime { drawerPeekRuntime = nil }
                    runtimes.attachWebRuntime(existingRuntime, to: board)
                }
            case .prepareLinkFocus(let boardID, let origin):
                _ = boardNavigation.prepareBoardLinkFocus(boardID, origin: origin)
            case .suppressMutationAnimation:
                onWindowEffect?(.suppressBoardMutationAnimation)
            case .focusInsertedBoard(let deskID):
                onWindowEffect?(.clearBoardInputRequests)
                boardNavigation.setFocusedDesk(deskID)
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            case .didInsert(let board):
                if let existingRuntime {
                    runtimes.updateBoard(
                        boardID: board.id, url: existingRuntime.webView.url, title: existingRuntime.webView.title)
                }
                if board.isWeb {
                    storage.recordOperation(.webBoardOpened)
                } else if board.isTerminal {
                    storage.recordOperation(.terminalBoardOpened)
                }
            case .focusTutorial(let boardID):
                boardNavigation.focusBoard(boardID, exitsDenMode: true)
                onWindowEffect?(.dismissTemporaryPresentation)
            case .didOpenInput:
                onWindowEffect?(.openBoardResult(nil))
            case .selectZmxSession:
                onWindowEffect?(.presentZmxSessions(returnsToOpenBoard: returnsToOpenBoard, selectedSessionName: nil))
            }
        }
    }

    func inputOpeningContext(preferredWidth: Double? = nil, afterBoardID: BoardID? = nil) -> InputOpening.Context {
        .init(
            width: preferredWidth ?? inheritedBoardWidth, target: boardCreationTarget(afterBoardID: afterBoardID),
            configuration: boardOpeningConfiguration)
    }

    @discardableResult
    func openBoard(
        input: String,
        preferredWidth: Double? = nil,
        afterBoardID: BoardID? = nil,
        opensFromOpenBoardPanel: Bool = false,
        zmxRootSessionName: String? = nil
    ) -> Bool {
        switch requestOpenBoard(
            input: input,
            preferredWidth: preferredWidth,
            afterBoardID: afterBoardID,
            opensFromOpenBoardPanel: opensFromOpenBoardPanel,
            zmxRootSessionName: zmxRootSessionName)
        {
        case .accepted:
            return true
        case .rejected(let message):
            if let message { onWindowEffect?(.openBoardResult(message)) }
            return false
        }
    }

    @discardableResult
    func requestOpenBoard(
        input: String,
        preferredWidth: Double? = nil,
        afterBoardID: BoardID? = nil,
        opensFromOpenBoardPanel: Bool = false,
        zmxRootSessionName: String? = nil
    ) -> BoardOpenResult {
        storage.boardCreation.open(
            boardOpeningRequest(
                input: input, preferredWidth: preferredWidth, afterBoardID: afterBoardID,
                zmxRootSessionName: zmxRootSessionName),
            notify: boardCreationNotifications(returnsToOpenBoard: opensFromOpenBoardPanel))
    }

    @discardableResult
    func openTutorialBoard(preferredWidth: Double? = nil, afterBoardID: BoardID? = nil) -> Bool {
        storage.boardCreation.openTutorial(
            width: preferredWidth ?? inheritedBoardWidth,
            target: boardCreationTarget(afterBoardID: afterBoardID),
            notify: boardCreationNotifications()) != nil
    }

    func dispatchDenOperationEvent(_ event: DenOperationEvent) {
        if let step = event.tutorialStep { storage.tutorialProgress.record(step) }
        storage.onDenOperationEvent(event)
    }

    func openBoard(recentItem: RecentItem, preferredWidth: Double? = nil, afterBoardID: BoardID? = nil) {
        openBoard(input: recentItem.displayText, preferredWidth: preferredWidth, afterBoardID: afterBoardID)
    }

    @discardableResult
    func createBoard(
        urlString: String,
        preferredWidth: Double? = nil,
        afterBoardID: BoardID? = nil,
        focus: Bool = true,
        origin: BoardOperationOrigin = .interactive,
        recentItem: RecentItem? = nil,
        deskID: DeskID? = nil,
        existingRuntime: WebRuntime? = nil
    ) -> BoardID? {
        storage.boardCreation.createWeb(
            urlString: urlString, width: preferredWidth ?? inheritedBoardWidth,
            searchEngine: preferences.searchEngine,
            target: boardCreationTarget(afterBoardID: afterBoardID, focus: focus, origin: origin, deskID: deskID),
            recentItem: recentItem,
            notify: boardCreationNotifications(existingRuntime: existingRuntime))
    }

    @discardableResult
    func createPopupBoard(
        _ popupWebView: WKWebView,
        requestedURL: URL?,
        fromBoardID: BoardID,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard let sourceIndices = context.boardIndices(for: fromBoardID) else { return false }
        let sourceBoard = state.desks[sourceIndices.deskOffset].boards[sourceIndices.boardOffset]
        guard sourceBoard.isWeb
        else { return false }

        let initialURL = requestedURL.flatMap { WebURLPolicy.isSupported($0) ? $0 : nil }
        let board = BoardState(
            label: initialURL?.host(percentEncoded: false) ?? "New Board",
            width: sourceBoard.width,
            currentSheetURL: initialURL)
        let focus = !modifierFlags.contains(.command) || modifierFlags.contains(.shift)
        let runtime = runtimes.webRuntime(for: board, popupWebView: popupWebView)
        guard runtime.webView === popupWebView else {
            runtimes.disposeRuntime(for: board.id)
            return false
        }
        guard
            insertBoard(
                board,
                afterBoardID: fromBoardID,
                focus: focus,
                origin: .interactive)
        else {
            runtimes.disposeRuntime(for: board.id)
            return false
        }

        return true
    }

    @discardableResult
    func createTerminalBoard(
        workingDirectory: String? = nil,
        preferredWidth: Double? = nil,
        afterBoardID: BoardID? = nil,
        focus: Bool = true,
        origin: BoardOperationOrigin = .interactive,
        recentItem: RecentItem? = nil,
        deskID: DeskID? = nil
    ) -> BoardID? {
        storage.boardCreation.createTerminal(
            workingDirectory: workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
            width: preferredWidth ?? inheritedBoardWidth,
            target: boardCreationTarget(afterBoardID: afterBoardID, focus: focus, origin: origin, deskID: deskID),
            recentItem: recentItem, notify: boardCreationNotifications())
    }

    @discardableResult
    func insertBoard(
        _ board: BoardState,
        afterBoardID: BoardID?,
        focus: Bool,
        origin: BoardOperationOrigin,
        deskID: DeskID? = nil
    ) -> Bool {
        storage.boardCreation.insert(
            board,
            target: boardCreationTarget(afterBoardID: afterBoardID, focus: focus, origin: origin, deskID: deskID),
            notify: boardCreationNotifications()) != nil
    }

    var inheritedBoardWidth: Double {
        focusedBoard?.width ?? BuiltInDeskPreset.boardWidth
    }

    @discardableResult
    func navigateFocusedBoard(urlString: String) -> Bool {
        guard let id = focusedBoard?.id,
            let url = storage.boardUpdates.navigate(
                id, to: urlString, searchEngine: preferences.searchEngine,
                beforeSave: {
                    onWindowEffect?(.dismissTemporaryPresentation)
                    onWindowEffect?(.exitDenMode)
                })
        else { return false }
        webRuntimes[id]?.load(url)
        return true
    }

    func renameFocusedBoard(to newLabel: String) {
        guard let id = focusedBoard?.id else { return }
        storage.boardUpdates.rename(id, to: newLabel) {
            onWindowEffect?(.dismissTemporaryPresentation)
            onWindowEffect?(.exitDenMode)
        }
    }

    func goBackInFocusedBoard() {
        runtimes.focusedWebRuntime?.goBack()
    }

    func goForwardInFocusedBoard() {
        runtimes.focusedWebRuntime?.goForward()
    }

    func goToFirstSheetInFocusedBoard() {
        guard
            let firstSheetURL = focusedBoard?.firstSheetURL,
            let currentSheetURL = focusedBoard?.currentSheetURL,
            currentSheetURL != firstSheetURL,
            let runtime = runtimes.focusedWebRuntime
        else { return }
        runtime.load(firstSheetURL)
    }

    func goToFirstSheetInBoard(_ boardID: BoardID) {
        guard context.boardIndices(for: boardID) != nil else { return }
        boardNavigation.focusBoard(boardID)
        goToFirstSheetInFocusedBoard()
    }

    func goToLatestSheetInFocusedBoard() {
        runtimes.focusedWebRuntime?.goToLatestSheet()
    }

    func goToLatestSheetInBoard(_ boardID: BoardID) {
        guard context.boardIndices(for: boardID) != nil else { return }
        boardNavigation.focusBoard(boardID)
        goToLatestSheetInFocusedBoard()
    }

    func goBackInBoard(_ boardID: BoardID) {
        guard context.boardIndices(for: boardID) != nil else { return }
        boardNavigation.focusBoard(boardID)
        runtimes.focusedWebRuntime?.goBack()
    }

    func goForwardInBoard(_ boardID: BoardID) {
        guard context.boardIndices(for: boardID) != nil else { return }
        boardNavigation.focusBoard(boardID)
        runtimes.focusedWebRuntime?.goForward()
    }

    func reloadFocusedBoard() {
        runtimes.focusedWebRuntime?.reload()
    }

    func reloadFocusedBoardFromOrigin() {
        runtimes.focusedWebRuntime?.reloadFromOrigin()
    }

    func reloadFocusedDeskSheets() {
        guard let desk = focusedDesk else { return }
        for board in desk.boards where board.isWeb {
            runtimes.webRuntime(for: board).reload()
        }
    }

    func handleTerminalURL(_ rawURL: String, boardID: BoardID) {
        guard
            let board = context.board(for: boardID),
            let link = TerminalLinkResolver.resolve(
                rawURL,
                relativeTo: board.terminalWorkingDirectory
                    ?? FileManager.default.homeDirectoryForCurrentUser.path)
        else { return }

        switch link {
        case .localFile(let fileURL):
            _ = NSWorkspace.shared.open(fileURL)
        case .web(let resolvedURL):
            _ = createBoard(
                urlString: resolvedURL.absoluteString,
                preferredWidth: board.width,
                afterBoardID: board.id,
                focus: true,
                recentItem: .url(resolvedURL))
        }
    }
}
