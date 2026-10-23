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
                _ = connection.boardOpening?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onOpenBoardInBackground: { [connection] url in
                _ = connection.boardOpening?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    focus: false,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onKeepInDrawer: { [connection] url in connection.drawer?.keepInDrawer(url, opensDrawer: false) },
            onEditCurrentSheet: { [connection] in
                connection.boardNavigation?.focusBoard(board.id)
                connection.onWindowEffect?(.presentEditBoardLink)
            },
            onOpenCurrentSheetInNewBoard: { [connection] url in
                connection.boardNavigation?.focusBoard(board.id)
                connection.onWindowEffect?(.presentOpenBoard(initialURL: url, afterBoardID: nil))
            },
            onPasteURLInNewBoard: { [connection] url in
                _ = connection.boardOpening?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onCopyURLSucceeded: { [connection] in
                connection.feedback?.publish("Copied Current Sheet URL.", severity: .success)
            },
            onCopyURLFailed: { [connection] in
                connection.feedback?.publish("Could not copy Current Sheet URL.", severity: .error)
            },
            onCopyMarkdownLinkSucceeded: { [connection] in
                connection.feedback?.publish("Copied Current Sheet Markdown link.", severity: .success)
            },
            onCopyMarkdownLinkFailed: { [connection] in
                connection.feedback?.publish("Could not copy Current Sheet Markdown link.", severity: .error)
            },
            onCopyBoardID: { [connection] in
                connection.boardNavigation?.copyBoardID(board.id)
            },
            onPasteURLFailed: { [connection] in
                connection.feedback?.publish("Clipboard does not contain a supported URL.", severity: .warning)
            },
            onOpenBoardPanel: { [connection] in
                connection.boardNavigation?.focusBoard(board.id)
                connection.onWindowEffect?(.presentOpenBoard(initialURL: nil, afterBoardID: nil))
            },
            onShowOverview: { [connection] in
                connection.boardNavigation?.focusBoard(board.id)
                connection.onWindowEffect?(
                    .presentOverview(
                        deskID: connection.presentedDeskID(),
                        boardID: connection.focusedBoardID()))
            },
            onShowEssentials: { [connection] in
                connection.boardNavigation?.focusBoard(board.id)
                connection.onWindowEffect?(.presentEssentialsPrefix)
            },
            onRemoveBoard: { [connection] in connection.boardRemoval?.removeBoard(board.id) },
            onRemoveBoardAndFocusNext: { [connection] in connection.boardRemoval?.removeBoard(board.id, focusNext: true)
            },
            onRestoreBoard: { [connection] in connection.boardRemoval?.restoreRecentlyRemovedBoard() },
            onFocusFirstBoard: { [connection] in connection.boardNavigation?.focusFirstBoardInDesk(containing: board.id)
            },
            onFocusLastBoard: { [connection] in connection.boardNavigation?.focusLastBoardInDesk(containing: board.id)
            },
            onFocusPreviousBoard: { [connection] in
                connection.boardNavigation?.focusBoard(board.id)
                connection.boardNavigation?.focusPreviousBoard()
            },
            onFocusNextBoard: { [connection] in
                connection.boardNavigation?.focusBoard(board.id)
                connection.boardNavigation?.focusNextBoard()
            },
            onGoToFirstSheet: { [connection] in connection.boardOpening?.goToFirstSheetInBoard(board.id) },
            onGoToLatestSheet: { [connection] in connection.boardOpening?.goToLatestSheetInBoard(board.id) },
            isSupportedSheetURL: WebURLPolicy.isSupported,
            onNavigateCurrentSheet: { [connection] url in
                connection.boardNavigation?.focusBoard(board.id)
                connection.boardOpening?.navigateFocusedBoard(urlString: url.absoluteString)
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
                connection.boardNavigation?.updateFullscreenStatus(boardID: id, isFullscreen: fullscreen)
            },
            onCreatePopupBoard: { [connection] webView, url, flags in
                connection.boardOpening?.createPopupBoard(
                    webView, requestedURL: url, fromBoardID: board.id, modifierFlags: flags) ?? false
            },
            onClosePopupBoard: { [weak self, connection] in self?.removeBoard(connection: connection) },
            onLinkActivated: { [connection] in connection.boardNavigation?.prepareBoardLinkFocus(board.id) },
            downloadActivityOwnerID: ObjectIdentifier(connection),
            onDownloadActivity: { [connection] in connection.onDownloadActivity?($0) },
            onDownloadFinished: { [connection] in
                connection.feedback?.publish("Downloaded \($0).", severity: .success)
            },
            onDownloadFailed: { [connection] in
                connection.feedback?.publish("Download failed: \($0)", severity: .error)
            },
            isFocused: { [connection] in connection.focusedBoardID() == board.id },
            restoreFocusedFirstResponder: { [connection] in connection.runtimes?.restoreFocusedFirstResponder() })
    }

    func terminalEvents(for board: BoardState, connection: RuntimeWindowConnection) -> TerminalRuntime.Events {
        .init(
            onClose: { [weak self, connection] in self?.removeBoard(connection: connection) },
            onFocus: { [connection] in connection.onWindowEffect?(.runtimeFocusedBoard(board.id)) },
            onWorkingDirectoryChange: { [weak self] in
                self?.storage?.boardUpdates.updateTerminal(board.id, workingDirectory: $0)
            },
            onTitleChange: { [weak self] in self?.storage?.boardUpdates.updateTerminal(board.id, title: $0) },
            onOpenURL: { [connection] in connection.boardOpening?.handleTerminalURL($0, boardID: board.id) },
            onNotification: { [weak self, connection] title, body in
                guard
                    let notification = self?.storage?.notificationOperations.record(
                        title: title, body: body, boardID: board.id)
                else { return }
                connection.onWindowEffect?(.notificationAdded(notification.id))
                connection.feedback?.publish(title: title, body: body, target: .notification(notification.id))
            })
    }

    private func removeBoard(connection: RuntimeWindowConnection) {
        if let removal = connection.boardRemoval {
            removal.removeBoard(boardID)
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
            for window in storage.windowConnections.allObjects {
                window.invalidateBoards?(removedIDs)
                for id in removedIDs {
                    window.onWindowEffect?(.boardRemoved(id))
                }
            }
        }
    }
}
