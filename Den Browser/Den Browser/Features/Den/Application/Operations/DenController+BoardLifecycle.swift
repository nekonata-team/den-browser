import DenApplication
import DenDomain
import DenPresentationModels
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
        let outcome = BoardOpening.open(
            input: input,
            width: preferredWidth ?? inheritedBoardWidth,
            afterBoardID: afterBoardID,
            zmxRootSessionName: zmxRootSessionName,
            configuration: BoardOpening.Configuration(
                searchEngine: preferences.searchEngine,
                zmxConfigured: zmxClient.isConfigured,
                zellijConfigured: zellijClient.isConfigured,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            directoryExists: { Self.directoryExists($0, fileManager: .default) },
            actions: BoardOpening.Actions(
                openTutorial: { [self] in openTutorialBoard(preferredWidth: $0, afterBoardID: $1) },
                insertBoard: { [self] in
                    insertBoard($0, afterBoardID: $1, focus: true, origin: .interactive, save: $2)
                },
                recordRecent: { [self] in saveRecentItem($0) }))
        switch outcome {
        case .openedBoard:
            onWindowEffect?(.openBoardResult(nil))
            return .accepted
        case .openedTutorial:
            return .accepted
        case .selectZmxSession:
            onWindowEffect?(
                .presentZmxSessions(returnsToOpenBoard: opensFromOpenBoardPanel, selectedSessionName: nil))
            return .accepted
        case .rejected(let failure):
            switch failure {
            case .zmxNotConfigured:
                return .rejected("Set an absolute zmx executable path in Settings > Terminal.")
            case .zellijNotConfigured:
                return .rejected("Set an absolute Zellij executable path in Settings > Terminal.")
            case .terminalDirectoryMissing(let path):
                return .rejected(TerminalInputError.missingDirectory(path).message)
            case .invalidInput, .creationFailed:
                return .rejected(nil)
            }
        }
    }

    @discardableResult
    func openTutorialBoard(preferredWidth: Double? = nil, afterBoardID: BoardID? = nil) -> Bool {
        if let tutorialBoard = state.desks.lazy.flatMap(\.boards).first(where: \.isTutorial) {
            focusBoard(tutorialBoard.id, exitsDenMode: true)
            onWindowEffect?(.dismissTemporaryPresentation)
            return true
        }

        let board = BoardState(
            width: preferredWidth ?? inheritedBoardWidth,
            tutorial: TutorialBoardState())
        return insertBoard(
            board,
            afterBoardID: afterBoardID,
            focus: true,
            origin: .interactive)
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
        deskID: DeskID? = nil
    ) -> BoardID? {
        guard let url = normalizedURL(from: urlString) else { return nil }
        let label = url.host(percentEncoded: false) ?? url.absoluteString
        let width = preferredWidth ?? inheritedBoardWidth
        let board = BoardState(label: label, width: width, currentSheetURL: url)
        guard
            insertBoard(
                board,
                afterBoardID: afterBoardID,
                focus: focus,
                origin: origin,
                deskID: deskID,
                save: recentItem == nil)
        else { return nil }
        if let recentItem {
            saveRecentItem(recentItem)
        }
        return board.id
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
            width: 360,
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
        let dir = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let board = BoardState(
            width: preferredWidth ?? inheritedBoardWidth,
            workingDirectory: dir
        )
        guard
            insertBoard(
                board,
                afterBoardID: afterBoardID,
                focus: focus,
                origin: origin,
                deskID: deskID,
                save: recentItem == nil)
        else { return nil }
        if let recentItem {
            saveRecentItem(recentItem)
        }
        return board.id
    }

    @discardableResult
    private func insertBoard(
        _ board: BoardState,
        afterBoardID: BoardID?,
        focus: Bool,
        origin: BoardOperationOrigin,
        deskID: DeskID? = nil,
        save: Bool = true
    ) -> Bool {
        guard
            let insertion = BoardInsertion.insert(
                board, in: state.desks,
                presentedDeskID: presentedDeskID,
                deskID: deskID,
                afterBoardID: afterBoardID, focus: focus)
        else { return false }
        let deskIndex = insertion.deskIndex.rawValue
        let insertionAfterBoardID = insertion.afterBoardID

        if !focus, let afterBoardID = insertionAfterBoardID {
            _ = prepareBoardLinkFocus(afterBoardID, origin: origin)
        }
        let isCLIBackgroundInsertion =
            origin == .cli
            && !focus
            && insertionAfterBoardID != nil
        let insert = { [self] in
            storage.state.desks[deskIndex] = insertion.desk
            if focus {
                onWindowEffect?(.clearBoardInputRequests)
                setFocusedDesk(state.desks[deskIndex].id)
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            }
            if save { self.save() }
        }
        if state.desks[deskIndex].boards.isEmpty || isCLIBackgroundInsertion {
            onWindowEffect?(.suppressBoardMutationAnimation)
        }
        insert()
        if board.isWeb {
            dispatchDenOperationEvent(.webBoardOpened)
        } else if board.isTerminal {
            dispatchDenOperationEvent(.terminalBoardOpened)
        }
        return true
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
        guard let indices = boardIndices(for: boardID) else { return }
        let isCLIBackgroundRemoval =
            origin == .cli
            && state.desks[indices.deskOffset].id == presentedDeskID
            && state.desks[indices.deskOffset].focusedBoardID != boardID
        let remove = { [self] in
            if isCLIBackgroundRemoval {
                _ = prepareBoardRemoval(origin: origin)
            }
            let sourceDesk = state.desks[indices.deskOffset]
            guard let removal = BoardRemoval.remove(boardID, from: sourceDesk, focusNext: focusNext) else { return }
            let removedIDs = Set(removal.removedBoards.map(\.id))
            storage.state.desks[indices.deskOffset] = removal.desk
            if sourceDesk.anchorBoardID.map({ removedIDs.contains($0) }) == true
                || anchorJumpOriginBoardIDByDesk[sourceDesk.id].map({ removedIDs.contains($0) }) == true
            {
                anchorJumpOriginBoardIDByDesk.removeValue(forKey: sourceDesk.id)
            }
            storage.recentlyRemovedBoards.insert(removal.historyEntry, at: 0)
            if recentlyRemovedBoards.count > Self.maximumRecentlyRemovedBoardCount {
                storage.recentlyRemovedBoards.removeLast()
            }
            for removedBoard in removal.removedBoards {
                if removedBoard.isInspection, let targetBoardID = removedBoard.sideBoardTargetBoardID {
                    webRuntimes[targetBoardID]?.stopInspection()
                }
                disposeRuntime(for: removedBoard.id)
            }

            onWindowEffect?(
                .overviewBoardRemoved(
                    boardID: boardID, deskID: sourceDesk.id, oldIndex: removal.historyEntry.sourceBoardIndex))
            invalidateReferences(toRemovedBoardIDs: removedIDs)
            save()
        }
        if isCLIBackgroundRemoval {
            onWindowEffect?(.suppressBoardMutationAnimation)
        }
        remove()
    }

    func restoreRecentlyRemovedBoard() {
        guard let recentlyRemovedBoard = recentlyRemovedBoards.first else {
            reportFeedback("No removed board to restore.", severity: .warning)
            return
        }

        let deskIndex: DeskIndex
        let restoredDesk: DeskState
        switch BoardRestoration.restore(
            recentlyRemovedBoard, in: state.desks, presentedDeskID: presentedDeskID)
        {
        case .restored(let destinationDeskIndex, let desk):
            deskIndex = destinationDeskIndex
            restoredDesk = desk
        case .focusExistingTutorial(let boardID):
            storage.recentlyRemovedBoards.removeFirst()
            focusBoard(boardID, exitsDenMode: true)
            reportFeedback("Tutorial Board is already open.", severity: .warning)
            return
        case .rejected(let failure):
            switch failure {
            case .sideBoardAlreadyExists:
                reportFeedback("A Side Board already exists for this Board.", severity: .warning)
            case .targetBoardMissing:
                reportFeedback("The target Board no longer exists.", severity: .warning)
            case .destinationDeskMissing:
                break
            }
            return
        }

        let board = recentlyRemovedBoard.board
        storage.state.desks[deskIndex.rawValue] = restoredDesk
        let deskID = state.desks[deskIndex.rawValue].id
        let changedDesk = setFocusedDesk(deskID)
        if !changedDesk && presentedDeskID == deskID {
            markNotificationsRead(for: board.id)
        }
        storage.recentlyRemovedBoards.removeFirst()
        save()
    }

    func duplicateFocusedBoard() {
        guard let source = focusedBoard, !source.isSideBoard, !source.isTutorial else { return }

        if source.isZmx {
            presentZmxDuplicationPanel(for: source)
            return
        }
        if let workingDirectory = source.terminalWorkingDirectory {
            let board = BoardState(
                label: source.label,
                width: source.width,
                workingDirectory: workingDirectory,
                customLabel: source.customLabel)
            insertBoard(board, afterBoardID: source.id, focus: true, origin: .interactive)
            return
        }
        if source.isZellij {
            let board = BoardState(
                label: source.label,
                width: source.width,
                zellijSessionName: source.zellijSessionName,
                customLabel: source.customLabel)
            insertBoard(board, afterBoardID: source.id, focus: true, origin: .interactive)
            return
        }
        duplicateBoard(
            source,
            currentSheetURL: source.currentSheetURL
        )
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
        guard
            let source = focusedBoard,
            let sessionName = source.zmxSessionName
        else { return }

        let client = zmxClient
        zmxCommandTask?.cancel()
        zmxCommandTask = Task { [weak self, client] in
            do {
                let context = try await client.duplicationContext(
                    for: sessionName,
                    savedRootSessionName: source.zmxRootSessionName)
                guard !Task.isCancelled, let self, self.focusedBoard?.id == source.id else { return }

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
                let board = BoardState(
                    label: source.label,
                    width: source.width,
                    zmxSessionName: newSessionName,
                    workingDirectory: workingDirectory,
                    rootSessionName: context.rootSessionName,
                    customLabel: source.customLabel)
                guard
                    self.insertBoard(
                        board,
                        afterBoardID: source.id,
                        focus: true,
                        origin: .interactive)
                else { return }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, self.focusedBoard?.id == source.id else { return }
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
        guard let source = focusedBoard, !source.isSideBoard else { return }

        if source.isZmx {
            duplicateFocusedZmxBoard(suffix: "")
            return
        }
        if source.isTerminal {
            duplicateFocusedBoard()
            return
        }
        guard let firstSheetURL = source.firstSheetURL else { return }
        duplicateBoard(
            source,
            currentSheetURL: firstSheetURL,
            firstSheetURL: firstSheetURL
        )
    }

    private func duplicateBoard(
        _ source: BoardState,
        currentSheetURL: URL?,
        firstSheetURL: URL? = nil
    ) {
        let board = BoardState(
            label: source.label,
            width: source.width,
            currentSheetURL: currentSheetURL,
            firstSheetURL: firstSheetURL,
            customLabel: source.customLabel,
            sheetNavigationPaused: source.sheetNavigationPaused
        )
        insertBoard(board, afterBoardID: source.id, focus: true, origin: .interactive)
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

    private func saveRecentItem(_ item: RecentItem) {
        let itemToSave: RecentItem
        if case .url(let url, nil) = item,
            let title = recentItems.first(where: { $0 == item })?.title
        {
            itemToSave = .url(url, title: title)
        } else {
            itemToSave = item
        }
        let original = recentItems
        storage.recentItems.removeAll { $0 == itemToSave }
        storage.recentItems.insert(itemToSave, at: 0)
        if recentItems.count > Self.maximumRecentItemCount {
            storage.recentItems.removeLast(recentItems.count - Self.maximumRecentItemCount)
        }
        if saveStateAndRecentItems() == false {
            storage.recentItems = original
        }
    }
}
