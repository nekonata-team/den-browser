import DenApplication
import DenDomain
import DenPresentationModels
import DenViews
import Foundation

extension DenController {
    func updateZmxRootSessionName(boardID: BoardID, rootSessionName: String?) {
        guard
            let rootSessionName,
            let indices = boardIndices(for: boardID),
            state.desks[indices.deskOffset].boards[indices.boardOffset].zmxRootSessionName != rootSessionName
        else { return }
        storage.state.desks[indices.deskOffset].boards[indices.boardOffset].zmxRootSessionName = rootSessionName
        save()
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

    private func tutorialBoardIndices() -> BoardIndices? {
        for deskIndex in state.desks.indices {
            if let boardIndex = state.desks[deskIndex].boards.firstIndex(where: \.isTutorial) {
                return BoardIndices(desk: DeskIndex(rawValue: deskIndex), board: BoardIndex(rawValue: boardIndex))
            }
        }
        return nil
    }

    func dispatchDenOperationEvent(_ event: DenOperationEvent) {
        advanceTutorial(for: event)
        storage.onDenOperationEvent(event)
    }

    private func advanceTutorial(for event: DenOperationEvent) {
        guard let step = event.tutorialStep else { return }
        guard let indices = tutorialBoardIndices(),
            case .tutorial(var tutorial) = state.desks[indices.deskOffset].boards[indices.boardOffset].kind
        else { return }

        guard tutorial.record(step: step) else { return }
        storage.state.desks[indices.deskOffset].boards[indices.boardOffset].kind = .tutorial(tutorial)
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
        guard recentItems.contains(item) else { return }
        let original = recentItems
        storage.recentItems.removeAll { $0 == item }
        if saveStateAndRecentItems() == false {
            storage.recentItems = original
        }
    }

    func clearRecent() {
        guard !recentItems.isEmpty else { return }
        let original = recentItems
        storage.recentItems = []
        if saveStateAndRecentItems() == false {
            storage.recentItems = original
        }
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
        guard
            let url = normalizedURL(from: urlString),
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return false }

        let boardID = state.desks[deskIndex.rawValue].boards[boardIndex.rawValue].id
        storage.state.desks[deskIndex.rawValue].boards[boardIndex.rawValue].currentSheetURL = url
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        save()
        webRuntimes[boardID]?.load(url)
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
        guard let sessionName = source.zmxSessionName else { return }
        let client = zmxClient
        zmxCommandTask?.cancel()
        zmxCommandTask = Task { [weak self, client] in
            do {
                let rootSessionName = try await client.resolvedRootSessionName(
                    for: sessionName,
                    savedRootSessionName: source.zmxRootSessionName)
                guard !Task.isCancelled, let self, self.focusedBoard?.id == source.id else { return }
                self.onWindowEffect?(.presentZmxDuplicationPanel(rootSessionName: rootSessionName))
            } catch {
                return
            }
        }
    }

    func duplicateFocusedZmxBoard(suffix: String) {
        guard let source = focusedBoard else { return }
        createZmxBoard(from: source, suffix: suffix, asSideBoard: false, focus: true)
    }

    private func createZmxBoard(from source: BoardState, suffix: String, asSideBoard: Bool, focus: Bool) {
        guard let sessionName = source.zmxSessionName else { return }

        let client = zmxClient
        zmxCommandTask?.cancel()
        zmxCommandTask = Task { [weak self, client] in
            do {
                let context = try await client.duplicationContext(
                    for: sessionName,
                    savedRootSessionName: source.zmxRootSessionName)
                guard !Task.isCancelled, let self else { return }
                if asSideBoard {
                    guard let indices = self.boardIndices(for: source.id),
                        !self.state.desks[indices.deskOffset].boards.contains(where: {
                            $0.sideBoardTargetBoardID == source.id
                        })
                    else { return }
                } else {
                    guard self.focusedBoard?.id == source.id else { return }
                }

                let denSessionNames = self.state.desks.flatMap { desk in
                    desk.boards.compactMap(\.zmxSessionName)
                }
                let newSessionName = ZmxSessionNameGenerator.nextName(
                    rootSessionName: context.rootSessionName,
                    suffix: suffix,
                    occupiedNames: context.activeSessionNames.union(denSessionNames))
                let workingDirectory =
                    source.terminalWorkingDirectory
                    ?? FileManager.default.homeDirectoryForCurrentUser.path
                var board = BoardState(
                    label: asSideBoard ? "Terminal Side Board" : source.label,
                    width: asSideBoard ? DenLayout.sideBoardInitialWidth : source.width,
                    zmxSessionName: newSessionName,
                    workingDirectory: workingDirectory,
                    rootSessionName: context.rootSessionName,
                    customLabel: asSideBoard ? nil : source.customLabel)
                if asSideBoard { board.role = .sideBoard(targetBoardID: source.id) }
                guard
                    self.insertBoard(
                        board,
                        afterBoardID: source.id,
                        focus: focus,
                        origin: focus ? .interactive : .cli)
                else { return }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self,
                    asSideBoard ? self.boardIndices(for: source.id) != nil : self.focusedBoard?.id == source.id
                else { return }
                self.reportFeedback(
                    "Could not inspect active zmx sessions: \(error.localizedDescription)",
                    severity: .warning)
            }
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
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            storage.state.desks[deskIndex.rawValue].boards[boardIndex.rawValue].customLabel = nil
        } else {
            storage.state.desks[deskIndex.rawValue].boards[boardIndex.rawValue].customLabel = trimmed
        }
        onWindowEffect?(.dismissTemporaryPresentation)
        onWindowEffect?(.exitDenMode)
        save()
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

    private func normalizedURL(from text: String) -> URL? {
        BoardInputResolver.normalizedURL(from: text, searchEngine: preferences.searchEngine)
    }
}
