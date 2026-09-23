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
                zmxSessionName: sessionName)
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
        let insertIndex: Int
        if let afterBoardID {
            guard let indices = boardIndices(for: afterBoardID) else { return false }
            deskIndex = indices.desk
            insertIndex = indices.board + 1
        } else {
            guard let focusedDeskIndex else { return false }
            deskIndex = focusedDeskIndex
            if let focusedBoardIndex = focusedBoardIndex(in: deskIndex) {
                insertIndex = focusedBoardIndex + 1
            } else {
                insertIndex = state.desks[deskIndex].boards.endIndex
            }
        }

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
        runtimes[boardID]?.load(url)
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
            let board = removeBoard(at: indices, focusNext: focusNext)
            recentlyRemovedBoards.insert(
                RecentlyRemovedBoard(
                    board: board,
                    sourceDeskID: state.desks[indices.desk].id,
                    sourceBoardIndex: indices.board
                ),
                at: 0
            )
            if recentlyRemovedBoards.count > Self.maximumRecentlyRemovedBoardCount {
                recentlyRemovedBoards.removeLast()
            }
            disposeRuntime(for: board.id)

            if isOverviewPresented, overviewSelection?.boardID == board.id {
                let deskBoards = state.desks[indices.desk].boards
                let nextBoardID =
                    indices.board < deskBoards.count
                    ? deskBoards[indices.board].id
                    : (indices.board > 0 ? deskBoards[indices.board - 1].id : deskBoards.first?.id)
                overviewSelection = OverviewSelection(deskID: state.desks[indices.desk].id, boardID: nextBoardID)
            }

            invalidateReferences(toRemovedBoardIDs: Set([board.id]))
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

        let deskIndex: Int
        let insertIndex: Int
        if let sourceDeskIndex = state.desks.firstIndex(where: { $0.id == recentlyRemovedBoard.sourceDeskID }) {
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

        let board = recentlyRemovedBoard.board
        state.desks[deskIndex].boards.insert(board, at: insertIndex)
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
        guard let source = focusedBoard else { return }

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
        guard let source = focusedBoard else { return }

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
        focusedRuntime?.webView.goBack()
    }

    func goForwardInFocusedBoard() {
        focusedRuntime?.webView.goForward()
    }

    func goToFirstSheetInFocusedBoard() {
        guard
            let firstSheetURL = focusedBoard?.firstSheetURL,
            let currentSheetURL = focusedBoard?.currentSheetURL,
            currentSheetURL != firstSheetURL,
            let runtime = focusedRuntime
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
            let webView = focusedRuntime?.webView,
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
        focusedRuntime?.webView.goBack()
    }

    func goForwardInBoard(_ boardID: UUID) {
        guard boardIndices(for: boardID) != nil else { return }
        focusBoard(boardID)
        focusedRuntime?.webView.goForward()
    }

    func reloadFocusedBoard() {
        focusedRuntime?.webView.reload()
    }

    func reloadFocusedBoardFromOrigin() {
        focusedRuntime?.webView.reloadFromOrigin()
    }

    func reloadFocusedDeskSheets() {
        guard let desk = focusedDesk else { return }
        for board in desk.boards where !board.isTerminal {
            runtime(for: board).webView.reload()
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
