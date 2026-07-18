import Foundation
import WebKit

extension DenStore {
    func runtime(for board: BoardState) -> BoardRuntime {
        if let runtime = runtimes[board.id] {
            return runtime
        }

        let runtime = BoardRuntime(
            board: board,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation
        ) {
            [weak self] url in
            self?.addBoard(urlString: url.absoluteString, afterBoardID: board.id)
        } onChange: {
            [weak self] boardID, url, title in
            self?.updateBoard(boardID: boardID, url: url, title: title)
        }
        runtimes[board.id] = runtime
        return runtime
    }

    func releaseRuntimes() {
        for runtime in runtimes.values {
            sheetNavigation.didClose(runtime.webView)
            runtime.webView.stopLoading()
            runtime.webView.navigationDelegate = nil
        }
        runtimes.removeAll()
    }

    var focusedRuntime: BoardRuntime? {
        guard
            let desk = focusedDesk,
            let focusedBoardID = desk.focusedBoardID,
            let board = desk.boards.first(where: { $0.id == focusedBoardID })
        else { return nil }
        return runtime(for: board)
    }

    private func updateBoard(boardID: UUID, url: URL?, title: String?) {
        guard let indices = boardIndices(for: boardID) else { return }
        if let url {
            state.desks[indices.desk].boards[indices.board].currentSheetURL = url
        }
        if let title, !title.isEmpty {
            state.desks[indices.desk].boards[indices.board].label = title
        }
        save()
    }
}
