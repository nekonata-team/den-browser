import Foundation

extension DenStore {
    func addBoard(urlString: String, preferredWidth: Double? = nil, afterBoardID: UUID? = nil) {
        guard let url = normalizedURL(from: urlString) else { return }
        let label = url.host(percentEncoded: false) ?? url.absoluteString
        let width = preferredWidth.map { min(max($0, 360), 980) } ?? 520
        let board = BoardState(label: label, width: width, currentSheetURL: url)

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
        state.desks[deskIndex].focusedBoardID = board.id
        state.focusedDeskID = state.desks[deskIndex].id
        setTemporaryContext(nil)
        isDenMode = false
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
        runtimes[boardID]?.webView.load(URLRequest(url: url))
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
        if let runtime = runtimes.removeValue(forKey: board.id) {
            sheetNavigation.didClose(runtime.webView)
            runtime.webView.stopLoading()
            runtime.webView.navigationDelegate = nil
        }

        save()
    }

    func restoreRecentlyRemovedBoard() {
        guard let recentlyRemovedBoard else { return }

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
        state.focusedDeskID = state.desks[deskIndex].id
        self.recentlyRemovedBoard = nil
        save()
    }

    func duplicateFocusedBoard() {
        guard
            let deskIndex = focusedDeskIndex,
            let boardIndex = focusedBoardIndex(in: deskIndex)
        else { return }

        let source = state.desks[deskIndex].boards[boardIndex]
        let board = BoardState(
            label: source.label,
            width: source.width,
            currentSheetURL: source.currentSheetURL,
            customLabel: source.customLabel
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

    private func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), SheetURLPolicy.isSupported(url) {
            return url
        }

        if !trimmed.contains("://"),
            !trimmed.contains(where: \.isWhitespace),
            let url = URL(string: "https://\(trimmed)"),
            let host = url.host,
            host == "localhost" || host.contains(".")
        {
            return url
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }
}
