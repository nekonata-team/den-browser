import AppKit
import DenApplication
import DenDomain
import DenPresentationModels
import Foundation
import WebKit

@MainActor
final class BoardRuntimeReceiver {
    private weak var storage: DenProfileResources?
    let boardID: BoardID

    init(storage: DenProfileResources, boardID: BoardID) {
        self.storage = storage
        self.boardID = boardID
    }

    func sheetNavigationActions(for board: BoardState, connection: RuntimeWindowConnection)
        -> SheetNavigationManager.Actions
    {
        .init(
            onOpenBoard: { [connection] url in
                _ = connection.controller?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onOpenBoardInBackground: { [connection] url in
                _ = connection.controller?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    focus: false,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onKeepInDrawer: { [connection] url in connection.controller?.keepInDrawer(url, opensDrawer: false) },
            onEditCurrentSheet: { [connection] in
                connection.controller?.focusBoard(board.id)
                connection.controller?.onWindowEffect?(.presentEditBoardLink)
            },
            onOpenCurrentSheetInNewBoard: { [connection] url in
                connection.controller?.focusBoard(board.id)
                connection.controller?.onWindowEffect?(.presentOpenBoard(initialURL: url, afterBoardID: nil))
            },
            onPasteURLInNewBoard: { [connection] url in
                _ = connection.controller?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onCopyURLSucceeded: { [connection] in
                connection.controller?.reportFeedback("Copied Current Sheet URL.", severity: .success)
            },
            onCopyURLFailed: { [connection] in
                connection.controller?.reportFeedback("Could not copy Current Sheet URL.", severity: .error)
            },
            onCopyMarkdownLinkSucceeded: { [connection] in
                connection.controller?.reportFeedback("Copied Current Sheet Markdown link.", severity: .success)
            },
            onCopyMarkdownLinkFailed: { [connection] in
                connection.controller?.reportFeedback("Could not copy Current Sheet Markdown link.", severity: .error)
            },
            onCopyBoardID: { [connection] in
                connection.controller?.copyBoardID(board.id)
            },
            onPasteURLFailed: { [connection] in
                connection.controller?.reportFeedback("Clipboard does not contain a supported URL.", severity: .warning)
            },
            onOpenBoardPanel: { [connection] in
                connection.controller?.focusBoard(board.id)
                connection.controller?.onWindowEffect?(.presentOpenBoard(initialURL: nil, afterBoardID: nil))
            },
            onShowOverview: { [connection] in
                connection.controller?.focusBoard(board.id)
                connection.controller?.onWindowEffect?(
                    .presentOverview(
                        deskID: connection.presentedDeskID(),
                        boardID: connection.focusedBoardID()))
            },
            onShowEssentials: { [connection] in
                connection.controller?.focusBoard(board.id)
                connection.controller?.onWindowEffect?(.presentEssentialsPrefix)
            },
            onRemoveBoard: { [connection] in connection.controller?.removeBoard(board.id) },
            onRemoveBoardAndFocusNext: { [connection] in connection.controller?.removeBoard(board.id, focusNext: true)
            },
            onRestoreBoard: { [connection] in connection.controller?.restoreRecentlyRemovedBoard() },
            onFocusFirstBoard: { [connection] in connection.controller?.focusFirstBoardInDesk(containing: board.id) },
            onFocusLastBoard: { [connection] in connection.controller?.focusLastBoardInDesk(containing: board.id) },
            onFocusPreviousBoard: { [connection] in
                connection.controller?.focusBoard(board.id)
                connection.controller?.focusPreviousBoard()
            },
            onFocusNextBoard: { [connection] in
                connection.controller?.focusBoard(board.id)
                connection.controller?.focusNextBoard()
            },
            onGoToFirstSheet: { [connection] in connection.controller?.goToFirstSheetInBoard(board.id) },
            onGoToLatestSheet: { [connection] in connection.controller?.goToLatestSheetInBoard(board.id) },
            isSupportedSheetURL: WebURLPolicy.isSupported,
            onNavigateCurrentSheet: { [connection] url in
                connection.controller?.focusBoard(board.id)
                connection.controller?.navigateFocusedBoard(urlString: url.absoluteString)
            })
    }

    func webEvents(for board: BoardState, connection: RuntimeWindowConnection) -> WebRuntime.Events {
        .init(
            onChange: { [weak self] id, url, title in
                guard let storage = self?.storage else { return }
                storage.boardUpdates.updateWeb(id, url: url, title: title, recents: storage.recents) {
                    storage.facingCache.invalidate(for: id)
                }
            },
            onFullscreenChange: { [connection] id, fullscreen in
                connection.controller?.updateFullscreenStatus(boardID: id, isFullscreen: fullscreen)
            },
            onCreatePopupBoard: { [connection] webView, url, flags in
                connection.controller?.createPopupBoard(
                    webView, requestedURL: url, fromBoardID: board.id, modifierFlags: flags) ?? false
            },
            onClosePopupBoard: { [weak self, connection] in self?.removeBoard(connection: connection) },
            onLinkActivated: { [connection] in connection.controller?.prepareBoardLinkFocus(board.id) },
            downloadActivityOwnerID: ObjectIdentifier(connection),
            onDownloadActivity: { [connection] in connection.controller?.handleDownloadActivity($0) },
            onDownloadFinished: { [connection] in
                connection.controller?.reportFeedback("Downloaded \($0).", severity: .success)
            },
            onDownloadFailed: { [connection] in
                connection.controller?.reportFeedback("Download failed: \($0)", severity: .error)
            },
            isFocused: { [connection] in connection.focusedBoardID() == board.id },
            restoreFocusedFirstResponder: { [connection] in connection.controller?.restoreFocusedFirstResponder() })
    }

    func terminalEvents(for board: BoardState, connection: RuntimeWindowConnection) -> TerminalRuntime.Events {
        .init(
            onClose: { [weak self, connection] in self?.removeBoard(connection: connection) },
            onFocus: { [connection] in connection.controller?.onWindowEffect?(.runtimeFocusedBoard(board.id)) },
            onWorkingDirectoryChange: { [weak self] in
                self?.storage?.boardUpdates.updateTerminal(board.id, workingDirectory: $0)
            },
            onTitleChange: { [weak self] in self?.storage?.boardUpdates.updateTerminal(board.id, title: $0) },
            onOpenURL: { [connection] in connection.controller?.handleTerminalURL($0, boardID: board.id) },
            onNotification: { [weak self, connection] title, body in
                guard
                    let notification = self?.storage?.notificationOperations.record(
                        title: title, body: body, boardID: board.id)
                else { return }
                connection.controller?.onWindowEffect?(.notificationAdded(notification.id))
                connection.controller?.reportFeedback(title: title, body: body, target: .notification(notification.id))
            })
    }

    private func removeBoard(connection: RuntimeWindowConnection) {
        if let controller = connection.controller {
            controller.removeBoard(boardID)
            return
        }
        guard let storage, let desk = storage.state.desks.first(where: { $0.boards.contains { $0.id == boardID } })
        else { return }
        storage.boardRemoval.remove(boardID, presentedDeskID: desk.id, origin: .cli) { notice in
            guard case .removed(_, let result) = notice else { return }
            let removedIDs = Set(result.removedBoards.map(\.id))
            for board in result.removedBoards {
                if board.isInspection, let target = board.sideBoardTargetBoardID {
                    storage.webRuntimes[target]?.stopInspection()
                }
                storage.facingCache.invalidate(for: board.id)
                storage.boardRuntimes.dispose(board.id)
            }
            for window in storage.drawerPresentations.allObjects {
                window.navigation.invalidateBoards(removedIDs)
                for id in removedIDs {
                    window.onWindowEffect?(.boardRemoved(id))
                }
            }
        }
    }
}
