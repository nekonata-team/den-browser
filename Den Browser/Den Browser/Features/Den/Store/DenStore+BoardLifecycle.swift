import Foundation

enum TerminalInputError: Error, Equatable {
    case missingDirectory(String)

    var message: String {
        switch self {
        case .missingDirectory(let path): "Terminal directory does not exist: \(path)"
        }
    }
}

enum ZellijInput: Equatable {
    case welcome
    case session(String)
}

extension DenStore {
    func openBoard(input: String, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) {
        if let zellij = Self.resolveZellijInput(input) {
            guard ZellijLaunchCommand.isValidExecutablePath(preferences.zellijPath) else {
                openBoardPanelMessage =
                    "Set an absolute Zellij executable path in Settings > Features > Terminal."
                return
            }
            let sessionName: String?
            switch zellij {
            case .welcome:
                sessionName = nil
            case .session(let name):
                sessionName = name
            }
            addZellijBoard(
                sessionName: sessionName,
                preferredWidth: preferredWidth,
                afterBoardID: afterBoardID)
            openBoardPanelMessage = nil
            return
        }

        if let terminal = Self.resolveTerminalInput(input) {
            switch terminal {
            case .success(let workingDirectory):
                addTerminalBoard(
                    workingDirectory: workingDirectory,
                    preferredWidth: preferredWidth,
                    afterBoardID: afterBoardID)
                openBoardPanelMessage = nil
            case .failure(let error):
                openBoardPanelMessage = error.message
            }
            return
        }
        guard let resolution = resolveOpenBoardInput(input) else { return }
        addBoard(urlString: input, preferredWidth: preferredWidth, afterBoardID: afterBoardID)
        guard input.count <= Self.maximumPersistedRecentInputLength else { return }
        saveRecentItem(resolution.item)
    }

    static func resolveZellijInput(_ input: String) -> ZellijInput? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first == ":zellij" else { return nil }
        guard parts.count == 2 else { return .welcome }

        let sessionName = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionName.isEmpty ? .welcome : .session(sessionName)
    }

    static func resolveTerminalInput(
        _ input: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError>? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first == ":terminal" else { return nil }

        let rawPath =
            parts.count == 1
            ? ""
            : String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if rawPath.isEmpty || rawPath == "~" {
            url = homeDirectory
        } else if rawPath.hasPrefix("~/") {
            url = homeDirectory.appending(path: String(rawPath.dropFirst(2)), directoryHint: .isDirectory)
        } else if rawPath.hasPrefix("/") {
            url = URL(fileURLWithPath: rawPath, isDirectory: true)
        } else {
            url = homeDirectory.appending(path: rawPath, directoryHint: .isDirectory)
        }
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.missingDirectory(standardized.path))
        }
        return .success(standardized.path)
    }

    func openBoard(recentItem: RecentItem, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) {
        openBoard(input: recentItem.displayText, preferredWidth: preferredWidth, afterBoardID: afterBoardID)
    }

    func clearRecent() {
        guard !recentItems.isEmpty else { return }
        let original = recentItems
        recentItems = []
        if onRecentItemsSave?([]) == false {
            recentItems = original
        }
    }

    func addBoard(
        urlString: String,
        preferredWidth: Double? = nil,
        afterBoardID: UUID? = nil,
        focus: Bool = true
    ) {
        guard let url = normalizedURL(from: urlString) else { return }
        let label = url.host(percentEncoded: false) ?? url.absoluteString
        let width = preferredWidth ?? 520
        let board = BoardState(label: label, width: width, currentSheetURL: url)
        insertBoard(board, afterBoardID: afterBoardID, focus: focus)
    }

    func addTerminalBoard(
        workingDirectory: String,
        preferredWidth: Double? = nil,
        afterBoardID: UUID? = nil,
        focus: Bool = true
    ) {
        let board = BoardState(
            width: preferredWidth ?? 520,
            workingDirectory: workingDirectory)
        insertBoard(board, afterBoardID: afterBoardID, focus: focus)
    }

    func addZellijBoard(
        sessionName: String?,
        preferredWidth: Double? = nil,
        afterBoardID: UUID? = nil,
        focus: Bool = true
    ) {
        let board = BoardState(
            width: preferredWidth ?? 520,
            zellijSessionName: sessionName)
        insertBoard(board, afterBoardID: afterBoardID, focus: focus)
    }

    private func insertBoard(_ board: BoardState, afterBoardID: UUID?, focus: Bool) {
        let deskIndex: Int
        let insertIndex: Int
        if let afterBoardID {
            guard let indices = boardIndices(for: afterBoardID) else { return }
            deskIndex = indices.desk
            insertIndex = indices.board + 1
        } else {
            guard let focusedDeskIndex else { return }
            deskIndex = focusedDeskIndex
            if let focusedBoardIndex = focusedBoardIndex(in: deskIndex) {
                insertIndex = focusedBoardIndex + 1
            } else {
                insertIndex = state.desks[deskIndex].boards.endIndex
            }
        }

        state.desks[deskIndex].boards.insert(board, at: insertIndex)
        if focus {
            state.desks[deskIndex].focusedBoardID = board.id
            setFocusedDesk(state.desks[deskIndex].id)
            setTemporaryContext(nil)
            isDenMode = false
        }
        save()
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

    func removeFocusedBoard() {
        guard let boardID = focusedDesk?.focusedBoardID else { return }
        removeBoard(boardID)
    }

    func removeBoard(_ boardID: UUID) {
        guard let indices = boardIndices(for: boardID) else { return }
        let board = removeBoard(at: indices)
        recentlyRemovedBoard = RecentlyRemovedBoard(
            board: board,
            sourceDeskID: state.desks[indices.desk].id,
            sourceBoardIndex: indices.board
        )
        if maximizedBoardID == board.id {
            maximizedBoardID = nil
        }
        disposeRuntime(for: board.id)

        save()
    }

    func restoreRecentlyRemovedBoard() {
        guard let recentlyRemovedBoard else {
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

        state.desks[deskIndex].boards.insert(recentlyRemovedBoard.board, at: insertIndex)
        state.desks[deskIndex].focusedBoardID = recentlyRemovedBoard.board.id
        setFocusedDesk(state.desks[deskIndex].id)
        self.recentlyRemovedBoard = nil
        save()
    }

    func duplicateFocusedBoard() {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let source = state.desks[deskIndex].boards[boardIndex]
        if let workingDirectory = source.terminalWorkingDirectory {
            let board = BoardState(
                label: source.label,
                width: source.width,
                workingDirectory: workingDirectory,
                customLabel: source.customLabel)
            state.desks[deskIndex].boards.insert(board, at: boardIndex + 1)
            state.desks[deskIndex].focusedBoardID = board.id
            isDenMode = false
            save()
            return
        }
        if source.isZellij {
            let board = BoardState(
                label: source.label,
                width: source.width,
                zellijSessionName: source.zellijSessionName,
                customLabel: source.customLabel)
            state.desks[deskIndex].boards.insert(board, at: boardIndex + 1)
            state.desks[deskIndex].focusedBoardID = board.id
            isDenMode = false
            save()
            return
        }
        duplicateBoard(
            source,
            deskIndex: deskIndex,
            boardIndex: boardIndex,
            currentSheetURL: source.currentSheetURL
        )
    }

    func duplicateFocusedBoardFromFirstSheet() {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let source = state.desks[deskIndex].boards[boardIndex]
        guard let firstSheetURL = source.firstSheetURL else { return }
        duplicateBoard(
            source,
            deskIndex: deskIndex,
            boardIndex: boardIndex,
            currentSheetURL: firstSheetURL,
            firstSheetURL: firstSheetURL
        )
    }

    private func duplicateBoard(
        _ source: BoardState,
        deskIndex: Int,
        boardIndex: Int,
        currentSheetURL: URL?,
        firstSheetURL: URL? = nil
    ) {
        let board = BoardState(
            label: source.label,
            width: source.width,
            currentSheetURL: currentSheetURL,
            firstSheetURL: firstSheetURL,
            customLabel: source.customLabel
        )
        sheetNavigation.setBoardPaused(
            sheetNavigation.isBoardPaused(source.id),
            for: board.id
        )
        state.desks[deskIndex].boards.insert(board, at: boardIndex + 1)
        state.desks[deskIndex].focusedBoardID = board.id
        isDenMode = false
        save()
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
        resolveOpenBoardInput(text).map { SheetURLPolicy.canonicalSheetURL($0.url) }
    }

    private func resolveOpenBoardInput(_ text: String) -> (url: URL, item: RecentItem)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), SheetURLPolicy.isSupported(url) {
            return (url, .url(url))
        }

        if !trimmed.contains("://"),
            !trimmed.contains(where: \.isWhitespace),
            let url = URL(string: "https://\(trimmed)"),
            let host = url.host,
            host == "localhost" || host.contains(".")
        {
            return (url, .url(url))
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = components?.url else { return nil }
        return (url, .search(trimmed))
    }

    private func saveRecentItem(_ item: RecentItem) {
        let original = recentItems
        recentItems.removeAll { $0 == item }
        recentItems.insert(item, at: 0)
        if recentItems.count > Self.maximumRecentItemCount {
            recentItems.removeLast(recentItems.count - Self.maximumRecentItemCount)
        }
        if onRecentItemsSave?(recentItems) == false {
            recentItems = original
        }
    }
}
