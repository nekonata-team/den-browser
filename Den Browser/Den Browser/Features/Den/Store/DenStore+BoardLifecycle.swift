import AppKit
import Foundation
import SwiftUI

extension DenStore {
    func openBoardFromClipboard(pasteboard: NSPasteboard? = nil) {
        let pasteboard = pasteboard ?? self.pasteboard
        guard
            let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            showToast("Clipboard is empty.", style: .warning)
            return
        }

        guard openBoard(input: text, afterBoardID: focusedBoard?.id) else {
            let message = openBoardPanelMessage ?? "Could not open board from clipboard."
            openBoardPanelMessage = nil
            showToast(message, style: .warning)
            return
        }
    }

    @discardableResult
    func openBoard(input: String, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) -> Bool {
        if input.trimmingCharacters(in: .whitespacesAndNewlines) == ":tutorial" {
            return openTutorialBoard(preferredWidth: preferredWidth, afterBoardID: afterBoardID)
        }

        if let zmx = Self.resolveZmxInput(input) {
            guard zmxClient.isConfigured else {
                openBoardPanelMessage =
                    "Set an absolute zmx executable path in Settings > Terminal."
                return false
            }
            guard case .session(let sessionName) = zmx else {
                showZmxSessions(returnsToOpenBoard: temporaryContext == .openBoard)
                return true
            }
            let board = BoardState(
                width: preferredWidth ?? inheritedBoardWidth,
                zmxSessionName: sessionName,
                rootSessionName: zmxSessions.rootSessionName(for: sessionName))
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
            openBoardPanelMessage = nil
            return true
        }

        if let zellij = Self.resolveZellijInput(input) {
            guard zellijClient.isConfigured else {
                openBoardPanelMessage =
                    "Set an absolute Zellij executable path in Settings > Terminal."
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
            openBoardPanelMessage = nil
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
                openBoardPanelMessage = nil
                return true
            case .failure(let error):
                openBoardPanelMessage = error.message
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
        return true
    }

    @discardableResult
    func openTutorialBoard(preferredWidth: Double? = nil, afterBoardID: UUID? = nil) -> Bool {
        if let tutorialBoard = state.desks.lazy.flatMap(\.boards).first(where: \.isTutorial) {
            focusBoard(tutorialBoard.id, exitsDenMode: true)
            hideOpenBoardPanel()
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
        guard let indices = tutorialBoardIndices(),
            case .tutorial(var tutorial) = state.desks[indices.desk].boards[indices.board].content
        else { return }

        var completedSteps = tutorial.completedSteps
        for step in TutorialBoardStep.allCases where !step.isRequired && step.completionEvents.contains(event) {
            completedSteps.insert(step)
        }
        if let nextStep = TutorialBoardStep.requiredSteps
            .first(where: { !completedSteps.contains($0) }),
            nextStep.completionEvents.contains(event)
        {
            completedSteps.insert(nextStep)
        }
        guard completedSteps != tutorial.completedSteps else { return }
        tutorial.completedSteps = completedSteps
        state.desks[indices.desk].boards[indices.board].content = .tutorial(tutorial)
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

    func openBoard(recentItem: RecentItem, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) {
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
        afterBoardID: UUID? = nil,
        focus: Bool = true,
        origin: BoardOperationOrigin = .interactive,
        recentItem: RecentItem? = nil
    ) -> UUID? {
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
                save: recentItem == nil)
        else { return nil }
        if let recentItem {
            saveRecentItem(recentItem)
        }
        return board.id
    }

    @discardableResult
    func createInspectionBoard(targetBoardID: UUID, focus: Bool = true) -> UUID? {
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
        fromBoardID: UUID,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard let sourceIndices = boardIndices(for: fromBoardID) else { return false }
        let sourceBoard = state.desks[sourceIndices.desk].boards[sourceIndices.board]
        guard sourceBoard.isWeb
        else { return false }

        let initialURL = requestedURL.flatMap { SheetURLPolicy.isSupported($0) ? $0 : nil }
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
        afterBoardID: UUID? = nil,
        focus: Bool = true,
        origin: BoardOperationOrigin = .interactive,
        recentItem: RecentItem? = nil
    ) -> UUID? {
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
        afterBoardID: UUID?,
        focus: Bool,
        origin: BoardOperationOrigin,
        save: Bool = true
    ) -> Bool {
        let deskIndex: Int
        if let afterBoardID {
            guard let indices = boardIndices(for: afterBoardID) else { return false }
            deskIndex = indices.desk
        } else {
            guard let focusedDeskIndex else { return false }
            deskIndex = focusedDeskIndex
        }
        let boards = state.desks[deskIndex].boards
        let anchorBoardID = afterBoardID ?? state.desks[deskIndex].focusedBoardID
        let anchorIndex = anchorBoardID.flatMap { id in boards.firstIndex(where: { $0.id == id }) }
        let groupEndIndex = anchorBoardID.flatMap { id in
            BoardGroup.containing(id, in: boards)?.boards.last.flatMap { member in
                boards.firstIndex(where: { $0.id == member.id })
            }
        }
        let insertIndex = (groupEndIndex ?? anchorIndex).map { $0 + 1 } ?? boards.endIndex

        if !focus, let afterBoardID {
            _ = prepareBoardLinkFocus(afterBoardID, origin: origin)
        }
        let isCLIBackgroundInsertion =
            origin == .cli
            && !focus
            && afterBoardID != nil
        let insert = { [self] in
            state.desks[deskIndex].boards.insert(board, at: insertIndex)
            if focus {
                pendingBoardLinkFocus = nil
                pendingBoardRemoval = nil
                state.desks[deskIndex].focusedBoardID = board.id
                setFocusedDesk(state.desks[deskIndex].id)
                setTemporaryContext(nil)
                isDenMode = false
            } else if state.desks[deskIndex].focusedBoardID == nil {
                state.desks[deskIndex].focusedBoardID = board.id
            }
            if save { self.save() }
        }
        if state.desks[deskIndex].boards.isEmpty || isCLIBackgroundInsertion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, insert)
        } else {
            insert()
        }
        if board.isWeb {
            dispatchDenOperationEvent(.webBoardOpened)
        } else if board.isTerminal {
            dispatchDenOperationEvent(.terminalBoardOpened)
        }
        return true
    }

    var inheritedBoardWidth: Double {
        focusedBoard?.width ?? boardWidth(toFit: 2) ?? BuiltInDeskPreset.boardWidth
    }

    func launchEssential(id: UUID) {
        guard let essential = essentials.first(where: { $0.id == id }) else {
            exitEssentialsPrefix()
            return
        }

        exitEssentialsPrefix()
        openBoardPanelMessage = nil
        guard openBoard(input: essential.input) else {
            let message = openBoardPanelMessage ?? "Could not open Essential '\(essential.name)'."
            openBoardPanelMessage = nil
            showToast(message, style: .warning)
            return
        }
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
        setTemporaryContext(nil)
        isDenMode = false
        save()
        webRuntimes[boardID]?.load(url)
        return true
    }

    func removeFocusedBoard(focusNext: Bool = false) {
        guard let boardID = focusedDesk?.focusedBoardID else { return }
        removeBoard(boardID, focusNext: focusNext)
    }

    func removeBoard(
        _ boardID: UUID,
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

            if isOverviewPresented, overviewSelection?.boardID == board.id {
                let deskBoards = state.desks[indices.desk].boards
                let nextBoardID =
                    indices.board < deskBoards.count
                    ? deskBoards[indices.board].id
                    : (indices.board > 0 ? deskBoards[indices.board - 1].id : deskBoards.first?.id)
                overviewSelection = OverviewSelection(deskID: state.desks[indices.desk].id, boardID: nextBoardID)
            }

            invalidateReferences(toRemovedBoardIDs: removedIDs)
            save()
        }
        if isCLIBackgroundRemoval {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, remove)
        } else {
            remove()
        }
    }

    func restoreRecentlyRemovedBoard() {
        guard let recentlyRemovedBoard = recentlyRemovedBoards.first else {
            showToast("No removed board to restore.", style: .warning)
            return
        }

        if recentlyRemovedBoard.board.isTutorial,
            let existingTutorialBoard = state.desks.lazy.flatMap(\.boards).first(where: \.isTutorial)
        {
            recentlyRemovedBoards.removeFirst()
            focusBoard(existingTutorialBoard.id, exitsDenMode: true)
            showToast("Tutorial Board is already open.", style: .warning)
            return
        }

        let deskIndex: Int
        let insertIndex: Int
        if let targetBoardID = recentlyRemovedBoard.board.sideBoardTargetBoardID,
            let targetIndices = boardIndices(for: targetBoardID)
        {
            let targetBoards = state.desks[targetIndices.desk].boards
            guard !targetBoards.contains(where: { $0.sideBoardTargetBoardID == targetBoardID }) else {
                showToast("A Side Board already exists for this Board.", style: .warning)
                return
            }
            deskIndex = targetIndices.desk
            insertIndex =
                BoardGroup.containing(targetBoardID, in: targetBoards)?.boards.last.flatMap { member in
                    targetBoards.firstIndex(where: { $0.id == member.id }).map { $0 + 1 }
                } ?? targetIndices.board + 1
        } else if recentlyRemovedBoard.board.isSideBoard {
            showToast("The target Board no longer exists.", style: .warning)
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
            showZmxDuplicationPanel()
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

    static func zmxRootSessionName(
        for board: BoardState,
        using client: ZmxClient
    ) async throws -> String? {
        guard let sessionName = board.zmxSessionName else { return nil }
        do {
            return
                try await client.rootSessionName(for: sessionName)
                ?? board.zmxRootSessionName
                ?? sessionName
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return board.zmxRootSessionName ?? sessionName
        }
    }

    func duplicateFocusedZmxBoard(suffix: String) {
        guard
            let source = focusedBoard,
            let sessionName = source.zmxSessionName
        else { return }

        let requiresOpenPanel = temporaryContext == .zmxDuplication
        let client = zmxClient
        zmxCommandTask?.cancel()
        zmxCommandTask = Task { [weak self, client] in
            do {
                let activeSessionNames = try await client.activeSessionNames()
                let rootSessionName =
                    try await Self.zmxRootSessionName(for: source, using: client)
                    ?? source.zmxRootSessionName
                    ?? sessionName
                guard !Task.isCancelled, let self, self.focusedBoard?.id == source.id else { return }
                guard !requiresOpenPanel || self.temporaryContext == .zmxDuplication else { return }

                let denSessionNames = self.state.desks.flatMap { desk in
                    desk.boards.compactMap(\.zmxSessionName)
                }
                let newSessionName = ZmxSessionNameGenerator.nextName(
                    rootSessionName: rootSessionName,
                    suffix: suffix,
                    occupiedNames: activeSessionNames.union(denSessionNames))
                let workingDirectory =
                    source.terminalWorkingDirectory
                    ?? FileManager.default.homeDirectoryForCurrentUser.path
                let board = BoardState(
                    label: source.label,
                    width: source.width,
                    zmxSessionName: newSessionName,
                    workingDirectory: workingDirectory,
                    rootSessionName: rootSessionName,
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
                self.showToast(
                    "Could not inspect active zmx sessions: \(error.localizedDescription)",
                    style: .warning)
            }
        }
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
        setTemporaryContext(nil)
        isDenMode = false
        save()
    }

    func goBackInFocusedBoard() {
        focusedWebRuntime?.webView.goBack()
    }

    func goForwardInFocusedBoard() {
        focusedWebRuntime?.webView.goForward()
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

    func goToFirstSheetInBoard(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        goToFirstSheetInFocusedBoard()
    }

    func goToLatestSheetInFocusedBoard() {
        guard
            let webView = focusedWebRuntime?.webView,
            let latestSheet = webView.backForwardList.forwardList.last
        else { return }
        webView.go(to: latestSheet)
    }

    func goToLatestSheetInBoard(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        goToLatestSheetInFocusedBoard()
    }

    func goBackInBoard(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        focusedWebRuntime?.webView.goBack()
    }

    func goForwardInBoard(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        focusedWebRuntime?.webView.goForward()
    }

    func reloadFocusedBoard() {
        focusedWebRuntime?.webView.reload()
    }

    func reloadFocusedBoardFromOrigin() {
        focusedWebRuntime?.webView.reloadFromOrigin()
    }

    func reloadFocusedDeskSheets() {
        guard let desk = focusedDesk else { return }
        for board in desk.boards where board.isWeb {
            webRuntime(for: board).webView.reload()
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
