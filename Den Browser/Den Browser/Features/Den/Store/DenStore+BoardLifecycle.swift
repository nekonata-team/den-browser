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

enum ZmxInput: Equatable {
    case missingSessionName
    case session(String)
}

extension DenStore {
    @discardableResult
    func openBoard(input: String, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) -> Bool {
        if let zmx = Self.resolveZmxInput(input) {
            guard case .session(let sessionName) = zmx else {
                openBoardPanelMessage = "Enter a zmx session name."
                return false
            }
            guard zmxClient.isConfigured else {
                openBoardPanelMessage =
                    "Set an absolute zmx executable path in Settings > Features > Terminal."
                return false
            }
            guard
                addZmxBoard(
                    sessionName: sessionName,
                    preferredWidth: preferredWidth,
                    afterBoardID: afterBoardID)
            else { return false }
            openBoardPanelMessage = nil
            if input.count <= Self.maximumPersistedRecentInputLength {
                saveRecentItem(.zmx(sessionName: sessionName))
            }
            return true
        }

        if let zellij = Self.resolveZellijInput(input) {
            guard zellijClient.isConfigured else {
                openBoardPanelMessage =
                    "Set an absolute Zellij executable path in Settings > Features > Terminal."
                return false
            }
            let sessionName: String?
            switch zellij {
            case .welcome:
                sessionName = nil
            case .session(let name):
                sessionName = name
            }
            guard
                addZellijBoard(
                    sessionName: sessionName,
                    preferredWidth: preferredWidth,
                    afterBoardID: afterBoardID)
            else { return false }
            openBoardPanelMessage = nil
            if input.count <= Self.maximumPersistedRecentInputLength {
                saveRecentItem(.zellij(sessionName: sessionName))
            }
            return true
        }

        if let terminal = Self.resolveTerminalInput(input) {
            switch terminal {
            case .success(let workingDirectory):
                guard
                    addTerminalBoard(
                        workingDirectory: workingDirectory,
                        preferredWidth: preferredWidth,
                        afterBoardID: afterBoardID)
                else { return false }
                openBoardPanelMessage = nil
                if input.count <= Self.maximumPersistedRecentInputLength {
                    saveRecentItem(.terminal(workingDirectory: workingDirectory))
                }
                return true
            case .failure(let error):
                openBoardPanelMessage = error.message
                return false
            }
        }
        guard let resolution = resolveOpenBoardInput(input) else { return false }
        guard addBoard(urlString: input, preferredWidth: preferredWidth, afterBoardID: afterBoardID) else {
            return false
        }
        guard input.count <= Self.maximumPersistedRecentInputLength else { return true }
        saveRecentItem(resolution.item)
        return true
    }

    static func resolveZellijInput(_ input: String) -> ZellijInput? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first == ":zellij" else { return nil }
        guard parts.count == 2 else { return .welcome }

        let sessionName = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionName.isEmpty ? .welcome : .session(sessionName)
    }

    static func resolveZmxInput(_ input: String) -> ZmxInput? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first == ":zmx" else { return nil }
        guard parts.count == 2 else { return .missingSessionName }

        let sessionName = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionName.isEmpty ? .missingSessionName : .session(sessionName)
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
        return validateTerminalWorkingDirectory(url.standardizedFileURL.path, fileManager: fileManager)
    }

    func openBoard(recentItem: RecentItem, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) {
        switch recentItem {
        case .url, .search:
            openBoard(input: recentItem.displayText, preferredWidth: preferredWidth, afterBoardID: afterBoardID)
        case .terminal(let workingDirectory):
            switch Self.validateTerminalWorkingDirectory(workingDirectory) {
            case .success(let resolvedWorkingDirectory):
                guard
                    addTerminalBoard(
                        workingDirectory: resolvedWorkingDirectory,
                        preferredWidth: preferredWidth,
                        afterBoardID: afterBoardID)
                else { return }
                openBoardPanelMessage = nil
                saveRecentItem(.terminal(workingDirectory: resolvedWorkingDirectory))
            case .failure(let error):
                openBoardPanelMessage = error.message
            }
        case .zellij(let sessionName):
            guard zellijClient.isConfigured else {
                openBoardPanelMessage =
                    "Set an absolute Zellij executable path in Settings > Features > Terminal."
                return
            }
            guard
                addZellijBoard(
                    sessionName: sessionName,
                    preferredWidth: preferredWidth,
                    afterBoardID: afterBoardID)
            else { return }
            openBoardPanelMessage = nil
            saveRecentItem(.zellij(sessionName: sessionName))
        case .zmx(let sessionName):
            let sessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionName.isEmpty else {
                openBoardPanelMessage = "Enter a zmx session name."
                return
            }
            guard zmxClient.isConfigured else {
                openBoardPanelMessage =
                    "Set an absolute zmx executable path in Settings > Features > Terminal."
                return
            }
            guard
                addZmxBoard(
                    sessionName: sessionName,
                    preferredWidth: preferredWidth,
                    afterBoardID: afterBoardID)
            else { return }
            openBoardPanelMessage = nil
            saveRecentItem(.zmx(sessionName: sessionName))
        }
    }

    static func validateTerminalWorkingDirectory(
        _ workingDirectory: String,
        fileManager: FileManager = .default
    ) -> Result<String, TerminalInputError> {
        let standardized = URL(fileURLWithPath: workingDirectory, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.missingDirectory(standardized.path))
        }
        return .success(standardized.path)
    }

    func clearRecent() {
        guard !recentItems.isEmpty else { return }
        let original = recentItems
        recentItems = []
        if onRecentItemsSave?([]) == false {
            recentItems = original
        }
    }

    @discardableResult
    func addBoard(
        urlString: String,
        preferredWidth: Double? = nil,
        afterBoardID: UUID? = nil,
        focus: Bool = true
    ) -> Bool {
        guard let url = normalizedURL(from: urlString) else { return false }
        let label = url.host(percentEncoded: false) ?? url.absoluteString
        let width = preferredWidth ?? inheritedBoardWidth
        let board = BoardState(label: label, width: width, currentSheetURL: url)
        return insertBoard(board, afterBoardID: afterBoardID, focus: focus)
    }

    @discardableResult
    func addTerminalBoard(
        workingDirectory: String,
        preferredWidth: Double? = nil,
        afterBoardID: UUID? = nil,
        focus: Bool = true
    ) -> Bool {
        let board = BoardState(
            width: preferredWidth ?? inheritedBoardWidth,
            workingDirectory: workingDirectory)
        return insertBoard(board, afterBoardID: afterBoardID, focus: focus)
    }

    @discardableResult
    func addZellijBoard(
        sessionName: String?,
        preferredWidth: Double? = nil,
        afterBoardID: UUID? = nil,
        focus: Bool = true
    ) -> Bool {
        let board = BoardState(
            width: preferredWidth ?? inheritedBoardWidth,
            zellijSessionName: sessionName)
        return insertBoard(board, afterBoardID: afterBoardID, focus: focus)
    }

    @discardableResult
    func addZmxBoard(
        sessionName: String,
        preferredWidth: Double? = nil,
        afterBoardID: UUID? = nil,
        focus: Bool = true
    ) -> Bool {
        let normalizedSessionName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionName.isEmpty else { return false }
        let board = BoardState(
            width: preferredWidth ?? inheritedBoardWidth,
            zmxSessionName: normalizedSessionName)
        return insertBoard(board, afterBoardID: afterBoardID, focus: focus)
    }

    @discardableResult
    private func insertBoard(_ board: BoardState, afterBoardID: UUID?, focus: Bool) -> Bool {
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

        state.desks[deskIndex].boards.insert(board, at: insertIndex)
        if focus {
            state.desks[deskIndex].focusedBoardID = board.id
            setFocusedDesk(state.desks[deskIndex].id)
            setTemporaryContext(nil)
            isDenMode = false
        }
        save()
        return true
    }

    private var inheritedBoardWidth: Double {
        focusedBoard?.width ?? 520
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

    func removeBoard(_ boardID: UUID, focusNext: Bool = false) {
        guard let indices = boardIndices(for: boardID) else { return }
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
        if maximizedBoardID == board.id {
            maximizedBoardID = nil
        }
        disposeRuntime(for: board.id)

        save()
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
        setFocusedDesk(state.desks[deskIndex].id)
        recentlyRemovedBoards.removeFirst()
        save()
    }

    func duplicateFocusedBoard() {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let source = state.desks[deskIndex].boards[boardIndex]
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

    func zmxRootSessionName(for board: BoardState) -> String? {
        guard let sessionName = board.zmxSessionName else { return nil }
        return
            zmxClient.rootSessionName(for: sessionName)
            ?? board.zmxRootSessionName
            ?? sessionName
    }

    @discardableResult
    func duplicateFocusedZmxBoard(suffix: String) -> Bool {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex),
            let sessionName = state.desks[deskIndex].boards[boardIndex].zmxSessionName
        else { return false }
        let source = state.desks[deskIndex].boards[boardIndex]

        guard let activeSessionNames = zmxClient.activeSessionNames() else {
            showToast("Could not inspect active zmx sessions.", style: .warning)
            return false
        }

        let denSessionNames = state.desks.flatMap { desk in
            desk.boards.compactMap(\.zmxSessionName)
        }
        let rootSessionName = zmxRootSessionName(for: source) ?? sessionName
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
        state.desks[deskIndex].boards.insert(board, at: boardIndex + 1)
        state.desks[deskIndex].focusedBoardID = board.id
        setTemporaryContext(nil)
        isDenMode = false
        save()
        saveRecentItem(.zmx(sessionName: newSessionName))
        return true
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
            customLabel: source.customLabel,
            sheetNavigationPaused: source.sheetNavigationPaused
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
