import DenApplication
import DenDomain
import DenPresentationModels
import DenViews
import Foundation

extension DenController {
    func updateZmxRootSessionName(boardID: BoardID, rootSessionName: String?) {
        storage.boardUpdates.recordZmxRoot(rootSessionName, for: boardID)
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

    static func resolveTerminalInput(
        _ input: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError>? {
        BoardInputResolver.resolveTerminalInput(
            input, homeDirectory: homeDirectory,
            directoryExists: { directoryExists($0, fileManager: fileManager) })
    }

    func openBoard(recentItem: RecentItem, preferredWidth: Double? = nil, afterBoardID: BoardID? = nil) {
        openBoard(input: recentItem.displayText, preferredWidth: preferredWidth, afterBoardID: afterBoardID)
    }

    static func validateTerminalWorkingDirectory(
        _ workingDirectory: String,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError> {
        BoardInputResolver.validateTerminalWorkingDirectory(
            workingDirectory, directoryExists: { directoryExists($0, fileManager: fileManager) })
    }

    private static func directoryExists(_ path: String, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func removeRecentItem(_ item: RecentItem) {
        storage.recents.remove(item)
    }

    func clearRecent() {
        storage.recents.clear()
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
    func createInspectionBoard(targetBoardID: BoardID, focus: Bool = true) -> BoardID? {
        guard let indices = boardIndices(for: targetBoardID) else { return nil }
        let targetBoard = state.desks[indices.deskOffset].boards[indices.boardOffset]
        guard targetBoard.isWeb else { return nil }
        if let existingSideBoard = state.desks[indices.deskOffset].boards.first(where: {
            $0.sideBoardTargetBoardID == targetBoardID
        }) {
            guard existingSideBoard.isInspection else { return nil }
            if focus { focusBoard(existingSideBoard.id, exitsDenMode: true) }
            if !focus { webRuntime(for: targetBoard).startInspectionCollection(highlightColor: nil) }
            return existingSideBoard.id
        }
        let board = BoardState(
            width: DenLayout.sideBoardInitialWidth,
            targetBoardID: targetBoardID
        )
        let targetRuntime = focus ? nil : webRuntime(for: targetBoard)
        guard insertBoard(board, afterBoardID: targetBoardID, focus: focus, origin: focus ? .interactive : .cli) else {
            return nil
        }
        targetRuntime?.startInspectionCollection(highlightColor: nil)
        return board.id
    }

    @discardableResult
    func createTerminalSideBoard(targetBoardID: BoardID, focus: Bool = true) -> BoardID? {
        guard let requestedIndices = boardIndices(for: targetBoardID) else { return nil }
        let requestedBoard = state.desks[requestedIndices.deskOffset].boards[requestedIndices.boardOffset]
        let primaryBoardID = requestedBoard.sideBoardTargetBoardID ?? requestedBoard.id
        guard let indices = boardIndices(for: primaryBoardID) else { return nil }
        let primaryBoard = state.desks[indices.deskOffset].boards[indices.boardOffset]
        guard primaryBoard.isTerminal else { return nil }

        if let existingSideBoard = state.desks[indices.deskOffset].boards.first(where: {
            $0.sideBoardTargetBoardID == primaryBoardID
        }) {
            guard existingSideBoard.isTerminal else { return nil }
            if focus { focusBoard(existingSideBoard.id, exitsDenMode: true) }
            return existingSideBoard.id
        }

        if primaryBoard.isZmx {
            createZmxBoard(from: primaryBoard, suffix: "", asSideBoard: true, focus: focus)
            return nil
        }

        let workingDirectory =
            primaryBoard.terminalWorkingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        var board = BoardState(
            label: "Terminal Side Board", width: DenLayout.sideBoardInitialWidth, workingDirectory: workingDirectory)
        board.role = .sideBoard(targetBoardID: primaryBoardID)
        guard
            insertBoard(
                board,
                afterBoardID: primaryBoardID,
                focus: focus,
                origin: focus ? .interactive : .cli)
        else { return nil }
        return board.id
    }

    @discardableResult
    func createPopupBoard(
        _ popupWebView: WKWebView,
        requestedURL: URL?,
        fromBoardID: BoardID,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard let sourceIndices = boardIndices(for: fromBoardID) else { return false }
        let sourceBoard = state.desks[sourceIndices.deskOffset].boards[sourceIndices.boardOffset]
        guard sourceBoard.isWeb
        else { return false }

        let initialURL = requestedURL.flatMap { WebURLPolicy.isSupported($0) ? $0 : nil }
        let board = BoardState(
            label: initialURL?.host(percentEncoded: false) ?? "New Board",
            width: sourceBoard.width,
            currentSheetURL: initialURL)
        let focus = !modifierFlags.contains(.command) || modifierFlags.contains(.shift)
        let runtime = webRuntime(for: board, popupWebView: popupWebView)
        guard runtime.webView === popupWebView else {
            disposeRuntime(for: board.id)
            return false
        }
        guard
            insertBoard(
                board,
                afterBoardID: fromBoardID,
                focus: focus,
                origin: .interactive)
        else {
            disposeRuntime(for: board.id)
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
    private func insertBoard(
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

    func removeFocusedBoard(focusNext: Bool = false) {
        guard let boardID = focusedDesk?.focusedBoardID else { return }
        removeBoard(boardID, focusNext: focusNext)
    }

    func removeBoard(
        _ boardID: BoardID,
        focusNext: Bool = false,
        origin: BoardOperationOrigin = .interactive
    ) {
        storage.boardRemoval.remove(
            boardID, presentedDeskID: presentedDeskID, focusNext: focusNext, origin: origin,
            notify: boardRemovalNotifications())
    }

    @discardableResult
    func restoreRecentlyRemovedBoard(present: Bool = true) -> BoardID? {
        let result = storage.boardRemoval.restore(
            presentedDeskID: presentedDeskID, present: present, notify: boardRemovalNotifications())
        return handleBoardRestorationResult(result, present: present)
    }

    func duplicateFocusedBoard() {
        guard let source = focusedBoard else { return }
        switch BoardDuplication.resolve(source) {
        case .create(let board):
            insertBoard(board, afterBoardID: source.id, focus: true, origin: .interactive)
        case .zmxSession:
            presentZmxDuplicationPanel(for: source)
        case .unavailable:
            break
        }
    }

    private func presentZmxDuplicationPanel(for source: BoardState) {
        let operations = zmxBoards
        let client = zmxClient
        let window = zmxWindowProvider()
        let notify = zmxBoardNotifications()
        zmxCommandTask?.cancel()
        zmxCommandTask = Task {
            await operations.prepareDuplication(source, client: client, window: window, notify: notify)
        }
    }

    func duplicateFocusedZmxBoard(suffix: String) {
        guard let source = focusedBoard else { return }
        createZmxBoard(from: source, suffix: suffix, asSideBoard: false, focus: true)
    }

    private func createZmxBoard(from source: BoardState, suffix: String, asSideBoard: Bool, focus: Bool) {
        guard source.zmxSessionName != nil else { return }
        let request = ZmxBoards.Duplication(
            source: source, suffix: suffix, asSideBoard: asSideBoard, focus: focus,
            width: asSideBoard ? DenLayout.sideBoardInitialWidth : source.width,
            workingDirectory: source.terminalWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path)
        let operations = zmxBoards
        let client = zmxClient
        let window = zmxWindowProvider()
        let notify = zmxBoardNotifications()
        zmxCommandTask?.cancel()
        zmxCommandTask = Task {
            await operations.duplicate(request, client: client, window: window, notify: notify)
        }
    }

    func cancelZmxDuplicationRequest() {
        zmxCommandTask?.cancel()
        zmxCommandTask = nil
    }

    func waitForZmxCommand() async {
        await zmxCommandTask?.value
    }

    func duplicateFocusedBoardFromFirstSheet() {
        guard let source = focusedBoard else { return }
        switch BoardDuplication.resolve(source, fromFirstSheet: true) {
        case .create(let board):
            insertBoard(board, afterBoardID: source.id, focus: true, origin: .interactive)
        case .zmxSession:
            duplicateFocusedZmxBoard(suffix: "")
        case .unavailable:
            break
        }
    }

    func renameFocusedBoard(to newLabel: String) {
        guard let id = focusedBoard?.id else { return }
        storage.boardUpdates.rename(id, to: newLabel) {
            onWindowEffect?(.dismissTemporaryPresentation)
            onWindowEffect?(.exitDenMode)
        }
    }

    func goBackInFocusedBoard() {
        focusedWebRuntime?.goBack()
    }

    func goForwardInFocusedBoard() {
        focusedWebRuntime?.goForward()
    }

    func goToFirstSheetInFocusedBoard() {
        guard
            let firstSheetURL = focusedBoard?.firstSheetURL,
            let currentSheetURL = focusedBoard?.currentSheetURL,
            currentSheetURL != firstSheetURL,
            let runtime = focusedWebRuntime
        else { return }
        runtime.load(firstSheetURL)
    }

    func goToFirstSheetInBoard(_ boardID: BoardID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        goToFirstSheetInFocusedBoard()
    }

    func goToLatestSheetInFocusedBoard() {
        focusedWebRuntime?.goToLatestSheet()
    }

    func goToLatestSheetInBoard(_ boardID: BoardID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        goToLatestSheetInFocusedBoard()
    }

    func goBackInBoard(_ boardID: BoardID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        focusedWebRuntime?.goBack()
    }

    func goForwardInBoard(_ boardID: BoardID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        focusedWebRuntime?.goForward()
    }

    func reloadFocusedBoard() {
        focusedWebRuntime?.reload()
    }

    func reloadFocusedBoardFromOrigin() {
        focusedWebRuntime?.reloadFromOrigin()
    }

    func reloadFocusedDeskSheets() {
        guard let desk = focusedDesk else { return }
        for board in desk.boards where board.isWeb {
            webRuntime(for: board).reload()
        }
    }
}
