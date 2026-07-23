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
            sheetNavigation: sheetNavigation,
            sheetScale: preferences.sheetScale,
            nativePictureInPictureEnabled: preferences.nativePictureInPictureEnabled
        ) {
            [weak self] url in
            self?.addBoard(
                urlString: url.absoluteString,
                preferredWidth: board.width,
                afterBoardID: board.id
            )
        } onChange: {
            [weak self] boardID, url, title in
            self?.updateBoard(boardID: boardID, url: url, title: title)
        } onFullscreenChange: {
            [weak self] boardID, isFullscreen in
            self?.updateFullscreenStatus(boardID: boardID, isFullscreen: isFullscreen)
        } onEditCurrentSheet: {
            [weak self] in
            self?.focusBoard(board.id)
            self?.showEditBoardLinkPanel()
        } onOpenCurrentSheetInNewBoard: {
            [weak self] url in
            self?.focusBoard(board.id)
            self?.showOpenBoardPanel(initialURL: url)
        } onPasteURLInNewBoard: {
            [weak self] url in
            self?.addBoard(
                urlString: url.absoluteString,
                preferredWidth: board.width,
                afterBoardID: board.id
            )
        }
        runtimes[board.id] = runtime
        return runtime
    }

    func applySheetScale(_ scale: Int) {
        for runtime in runtimes.values {
            runtime.webView.pageZoom = CGFloat(scale) / 100
        }
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

    func updateBoard(boardID: UUID, url: URL?, title: String?) {
        guard let indices = boardIndices(for: boardID) else { return }
        var changed = false
        if let url,
            SheetURLPolicy.isSupported(url),
            state.desks[indices.desk].boards[indices.board].currentSheetURL != url
        {
            state.desks[indices.desk].boards[indices.board].currentSheetURL = url
            changed = true
        }
        if let title, !title.isEmpty, state.desks[indices.desk].boards[indices.board].label != title {
            state.desks[indices.desk].boards[indices.board].label = title
            changed = true
        }
        if changed {
            save()
        }
    }
}
