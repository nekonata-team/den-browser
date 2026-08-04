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
            nativePictureInPictureEnabled: preferences.nativePictureInPictureEnabled,
            sheetNavigationActions: .init(
                onOpenBoard: { [weak self] url in
                    self?.addBoard(
                        urlString: url.absoluteString,
                        preferredWidth: board.width,
                        afterBoardID: board.id
                    )
                },
                onOpenBoardInBackground: { [weak self] url in
                    self?.addBoard(
                        urlString: url.absoluteString,
                        preferredWidth: board.width,
                        afterBoardID: board.id,
                        focus: false
                    )
                },
                onKeepInDrawer: { [weak self] url in
                    self?.keepInDrawer(url, opensDrawer: false)
                },
                onEditCurrentSheet: { [weak self] in
                    self?.focusBoard(board.id)
                    self?.showEditBoardLinkPanel()
                },
                onOpenCurrentSheetInNewBoard: { [weak self] url in
                    self?.focusBoard(board.id)
                    self?.showOpenBoardPanel(initialURL: url)
                },
                onPasteURLInNewBoard: { [weak self] url in
                    self?.addBoard(
                        urlString: url.absoluteString,
                        preferredWidth: board.width,
                        afterBoardID: board.id
                    )
                },
                onOpenBoardPanel: { [weak self] in
                    self?.focusBoard(board.id)
                    self?.showOpenBoardPanel()
                },
                onShowOverview: { [weak self] in
                    self?.focusBoard(board.id)
                    self?.showOverview()
                },
                onRemoveBoard: { [weak self] in
                    self?.removeBoard(board.id)
                },
                onRestoreBoard: { [weak self] in
                    self?.restoreRecentlyRemovedBoard()
                }
            ),
            events: .init(
                onChange: { [weak self] boardID, url, title in
                    self?.updateBoard(boardID: boardID, url: url, title: title)
                },
                onFullscreenChange: { [weak self] boardID, isFullscreen in
                    self?.updateFullscreenStatus(boardID: boardID, isFullscreen: isFullscreen)
                },
                onDownloadFinished: { [weak self] filename in
                    self?.showToast("Downloaded \(filename).", style: .success)
                },
                onDownloadFailed: { [weak self] message in
                    self?.showToast("Download failed: \(message)", style: .error)
                }
            )
        )
        runtimes[board.id] = runtime
        return runtime
    }

    func applySheetScale(_ scale: Int) {
        for runtime in runtimes.values {
            runtime.webView.pageZoom = CGFloat(scale) / 100
        }
        drawerPreviewRuntime?.webView.pageZoom = CGFloat(scale) / 100
    }

    func releaseRuntimes() {
        for runtime in runtimes.values {
            runtime.dispose()
        }
        runtimes.removeAll()
        releaseDrawerPreview()
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
        if let url, SheetURLPolicy.isSupported(url) {
            let canonicalURL = SheetURLPolicy.canonicalSheetURL(url)
            if state.desks[indices.desk].boards[indices.board].currentSheetURL != canonicalURL {
                state.desks[indices.desk].boards[indices.board].currentSheetURL = canonicalURL
                changed = true
            }
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
