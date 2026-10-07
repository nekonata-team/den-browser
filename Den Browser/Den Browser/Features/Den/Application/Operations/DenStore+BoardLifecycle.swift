import DenDomain
import Foundation

extension DenStore {
    func updateZmxRootSessionName(boardID: BoardID, rootSessionName: String?) {
        guard
            let rootSessionName,
            let indices = boardIndices(for: boardID),
            state.desks[indices.desk].boards[indices.board].zmxRootSessionName != rootSessionName
        else { return }
        state.desks[indices.desk].boards[indices.board].zmxRootSessionName = rootSessionName
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
        if input.trimmingCharacters(in: .whitespacesAndNewlines) == ":tutorial" {
            return openTutorialBoard(preferredWidth: preferredWidth, afterBoardID: afterBoardID)
        }

        if let zmx = Self.resolveZmxInput(input) {
            guard zmxClient.isConfigured else {
                onWindowEffect?(.openBoardResult("Set an absolute zmx executable path in Settings > Terminal."))
                return false
            }
            guard case .session(let sessionName) = zmx else {
                onWindowEffect?(
                    .presentZmxSessions(
                        returnsToOpenBoard: opensFromOpenBoardPanel,
                        selectedSessionName: nil))
                return true
            }
            let board = BoardState(
                width: preferredWidth ?? inheritedBoardWidth,
                zmxSessionName: sessionName,
                rootSessionName: zmxRootSessionName)
            let recentItem =
                input.count <= Self.maximumPersistedRecentInputLength
                ? RecentItem.zmx(sessionName: sessionName)
                : nil
            guard
                insertBoard(
                    board,
                    afterBoardID: afterBoardID,
                    focus: true,
                    origin: .interactive,
                    save: recentItem == nil)
            else { return false }
            if let recentItem {
                saveRecentItem(recentItem)
            }
            onWindowEffect?(.openBoardResult(nil))
            return true
        }

        if let zellij = Self.resolveZellijInput(input) {
            guard zellijClient.isConfigured else {
                onWindowEffect?(.openBoardResult("Set an absolute Zellij executable path in Settings > Terminal."))
                return false
            }
            let sessionName: String?
            switch zellij {
            case .welcome:
                sessionName = nil
            case .session(let name):
                sessionName = name
            }
            let board = BoardState(
                width: preferredWidth ?? inheritedBoardWidth,
                zellijSessionName: sessionName)
            let recentItem =
                input.count <= Self.maximumPersistedRecentInputLength
                ? RecentItem.zellij(sessionName: sessionName)
                : nil
            guard
                insertBoard(
                    board,
                    afterBoardID: afterBoardID,
                    focus: true,
                    origin: .interactive,
                    save: recentItem == nil)
            else { return false }
            if let recentItem {
                saveRecentItem(recentItem)
            }
            onWindowEffect?(.openBoardResult(nil))
            return true
        }

        if let terminal = Self.resolveTerminalInput(input) {
            switch terminal {
            case .success(let workingDirectory):
                let recentItem =
                    input.count <= Self.maximumPersistedRecentInputLength
                    ? RecentItem.terminal(workingDirectory: workingDirectory)
                    : nil
                guard
                    createTerminalBoard(
                        workingDirectory: workingDirectory,
                        preferredWidth: preferredWidth,
                        afterBoardID: afterBoardID,
                        recentItem: recentItem) != nil
                else { return false }
                onWindowEffect?(.openBoardResult(nil))
                return true
            case .failure(let error):
                onWindowEffect?(.openBoardResult(error.message))
                return false
            }
        }
        guard let resolution = resolveOpenBoardInput(input) else { return false }
        let recentItem = input.count <= Self.maximumPersistedRecentInputLength ? resolution.item : nil
        guard
            createBoard(
                urlString: input,
                preferredWidth: preferredWidth,
                afterBoardID: afterBoardID,
                recentItem: recentItem) != nil
        else {
            return false
        }
        onWindowEffect?(.openBoardResult(nil))
        return true
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

    private func tutorialBoardIndices() -> (desk: Int, board: Int)? {
        for deskIndex in state.desks.indices {
            if let boardIndex = state.desks[deskIndex].boards.firstIndex(where: \.isTutorial) {
                return (deskIndex, boardIndex)
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
            case .tutorial(var tutorial) = state.desks[indices.desk].boards[indices.board].kind
        else { return }

        guard tutorial.record(step: step) else { return }
        state.desks[indices.desk].boards[indices.board].kind = .tutorial(tutorial)
    }

    static func resolveZellijInput(_ input: String) -> ZellijInput? {
        BoardInputResolver.resolveZellijInput(input)
    }

    static func resolveZmxInput(_ input: String) -> ZmxInput? {
        BoardInputResolver.resolveZmxInput(input)
    }

    static func resolveTerminalInput(
        _ input: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError>? {
        BoardInputResolver.resolveTerminalInput(input, homeDirectory: homeDirectory, fileManager: fileManager)
    }

    func openBoard(recentItem: RecentItem, preferredWidth: Double? = nil, afterBoardID: BoardID? = nil) {
        openBoard(input: recentItem.displayText, preferredWidth: preferredWidth, afterBoardID: afterBoardID)
    }

    static func validateTerminalWorkingDirectory(
        _ workingDirectory: String,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError> {
        BoardInputResolver.validateTerminalWorkingDirectory(workingDirectory, fileManager: fileManager)
    }

    func clearRecent() {
        guard !recentItems.isEmpty else { return }
        let original = recentItems
        recentItems = []
        if saveStateAndRecentItems() == false {
            recentItems = original
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
        let targetBoard = state.desks[indices.desk].boards[indices.board]
        guard targetBoard.isWeb else { return nil }
        if let existingSideBoard = state.desks[indices.desk].boards.first(where: {
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
        let sourceBoard = state.desks[sourceIndices.desk].boards[sourceIndices.board]
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
        let deskIndex: Int
        if let deskID {
            guard let index = state.desks.firstIndex(where: { $0.id == deskID }) else { return false }
            deskIndex = index
        } else if let afterBoardID {
            guard let indices = boardIndices(for: afterBoardID) else { return false }
            deskIndex = indices.desk
        } else {
            guard let focusedDeskIndex else { return false }
            deskIndex = focusedDeskIndex
        }
        let insertionAfterBoardID: BoardID?
        if let afterBoardID,
            let indices = boardIndices(for: afterBoardID),
            indices.desk == deskIndex
        {
            insertionAfterBoardID = afterBoardID
        } else {
            guard deskID != nil || afterBoardID == nil else { return false }
            insertionAfterBoardID = nil
        }
        let boards = state.desks[deskIndex].boards
        let anchorBoardID = insertionAfterBoardID ?? state.desks[deskIndex].focusedBoardID
        let anchorIndex = anchorBoardID.flatMap { id in boards.firstIndex(where: { $0.id == id }) }
        let groupEndIndex = anchorBoardID.flatMap { id in
            BoardGroup.containing(id, in: boards)?.boards.last.flatMap { member in
                boards.firstIndex(where: { $0.id == member.id })
            }
        }
        let insertIndex = (groupEndIndex ?? anchorIndex).map { $0 + 1 } ?? boards.endIndex

        if !focus, let afterBoardID = insertionAfterBoardID {
            _ = prepareBoardLinkFocus(afterBoardID, origin: origin)
        }
        let isCLIBackgroundInsertion =
            origin == .cli
            && !focus
            && insertionAfterBoardID != nil
        let insert = { [self] in
            state.desks[deskIndex].boards.insert(board, at: insertIndex)
            if focus {
                onWindowEffect?(.clearBoardInputRequests)
                state.desks[deskIndex].focusedBoardID = board.id
                setFocusedDesk(state.desks[deskIndex].id)
                onWindowEffect?(.dismissTemporaryPresentation)
                onWindowEffect?(.exitDenMode)
            } else if state.desks[deskIndex].focusedBoardID == nil {
                state.desks[deskIndex].focusedBoardID = board.id
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

        let boardID = state.desks[deskIndex].boards[boardIndex].id
        state.desks[deskIndex].boards[boardIndex].currentSheetURL = url
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
            && state.desks[indices.desk].id == presentedDeskID
            && state.desks[indices.desk].focusedBoardID != boardID
        let remove = { [self] in
            if isCLIBackgroundRemoval {
                _ = prepareBoardRemoval(origin: origin)
            }
            let sourceDeskID = state.desks[indices.desk].id
            let board = state.desks[indices.desk].boards[indices.board]
            let groupBoards =
                board.isSideBoard
                ? [board]
                : (BoardGroup.containing(board.id, in: state.desks[indices.desk].boards)?.boards ?? [board])
            let removedIDs = Set(groupBoards.map(\.id))
            let removed = groupBoards.filter { $0.id != board.id }
            for member in groupBoards.reversed() {
                guard let memberIndex = state.desks[indices.desk].boards.firstIndex(where: { $0.id == member.id })
                else { continue }
                _ = removeBoard(at: (desk: indices.desk, board: memberIndex), focusNext: focusNext)
            }
            recentlyRemovedBoards.insert(
                RecentlyRemovedBoard(
                    board: board,
                    sideBoard: removed.first,
                    sourceDeskID: sourceDeskID,
                    sourceBoardIndex: indices.board
                ),
                at: 0
            )
            if recentlyRemovedBoards.count > Self.maximumRecentlyRemovedBoardCount {
                recentlyRemovedBoards.removeLast()
            }
            for removedBoard in groupBoards {
                if removedBoard.isInspection, let targetBoardID = removedBoard.sideBoardTargetBoardID {
                    webRuntimes[targetBoardID]?.stopInspection()
                }
                disposeRuntime(for: removedBoard.id)
            }

            onWindowEffect?(
                .overviewBoardRemoved(boardID: board.id, deskID: sourceDeskID, oldIndex: indices.board))
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

        if recentlyRemovedBoard.board.isTutorial,
            let existingTutorialBoard = state.desks.lazy.flatMap(\.boards).first(where: \.isTutorial)
        {
            recentlyRemovedBoards.removeFirst()
            focusBoard(existingTutorialBoard.id, exitsDenMode: true)
            reportFeedback("Tutorial Board is already open.", severity: .warning)
            return
        }

        let deskIndex: Int
        let insertIndex: Int
        if let targetBoardID = recentlyRemovedBoard.board.sideBoardTargetBoardID,
            let targetIndices = boardIndices(for: targetBoardID)
        {
            let targetBoards = state.desks[targetIndices.desk].boards
            guard !targetBoards.contains(where: { $0.sideBoardTargetBoardID == targetBoardID }) else {
                reportFeedback("A Side Board already exists for this Board.", severity: .warning)
                return
            }
            deskIndex = targetIndices.desk
            insertIndex =
                BoardGroup.containing(targetBoardID, in: targetBoards)?.boards.last.flatMap { member in
                    targetBoards.firstIndex(where: { $0.id == member.id }).map { $0 + 1 }
                } ?? targetIndices.board + 1
        } else if recentlyRemovedBoard.board.isSideBoard {
            reportFeedback("The target Board no longer exists.", severity: .warning)
            return
        } else if let sourceDeskIndex = state.desks.firstIndex(where: { $0.id == recentlyRemovedBoard.sourceDeskID }) {
            deskIndex = sourceDeskIndex
            insertIndex = min(recentlyRemovedBoard.sourceBoardIndex, state.desks[deskIndex].boards.endIndex)
        } else {
            guard let focusedDeskIndex else { return }
            deskIndex = focusedDeskIndex
            if let focusedBoardIndex = focusedBoardIndex(in: deskIndex) {
                insertIndex = focusedBoardIndex + 1
            } else {
                insertIndex = state.desks[deskIndex].boards.endIndex
            }
        }

        let boards = state.desks[deskIndex].boards
        var insertionIndex = min(max(insertIndex, 0), boards.count)
        if insertionIndex > 0, insertionIndex < boards.count {
            let precedingGroup = BoardGroup.containing(boards[insertionIndex - 1].id, in: boards)
            if let lastMember = precedingGroup?.boards.last,
                let lastMemberIndex = boards.lastIndex(where: { $0.id == lastMember.id }),
                insertionIndex <= lastMemberIndex
            {
                insertionIndex = lastMemberIndex + 1
            }
        }

        let board = recentlyRemovedBoard.board
        let restoredBoards = [board] + (recentlyRemovedBoard.sideBoard.map { [$0] } ?? [])
        state.desks[deskIndex].boards.insert(contentsOf: restoredBoards, at: insertionIndex)
        state.desks[deskIndex].focusedBoardID = board.id
        let deskID = state.desks[deskIndex].id
        let changedDesk = setFocusedDesk(deskID)
        if !changedDesk && presentedDeskID == deskID {
            markNotificationsRead(for: board.id)
        }
        recentlyRemovedBoards.removeFirst()
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
            state.desks[deskIndex].boards[boardIndex].customLabel = nil
        } else {
            state.desks[deskIndex].boards[boardIndex].customLabel = trimmed
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

    private func resolveOpenBoardInput(_ text: String) -> (url: URL, item: RecentItem)? {
        BoardInputResolver.resolveOpenBoardInput(text, searchEngine: preferences.searchEngine)
    }

    private func saveRecentItem(_ item: RecentItem) {
        let original = recentItems
        recentItems.removeAll { $0 == item }
        recentItems.insert(item, at: 0)
        if recentItems.count > Self.maximumRecentItemCount {
            recentItems.removeLast(recentItems.count - Self.maximumRecentItemCount)
        }
        if saveStateAndRecentItems() == false {
            recentItems = original
        }
    }
}
