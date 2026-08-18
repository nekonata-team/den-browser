import Foundation
import WebKit

extension DenStore {
    func runtime(for board: BoardState) -> BoardRuntime {
        precondition(!board.isTerminal, "Terminal Board cannot create a web runtime")
        let actions = sheetNavigationActions(for: board)
        let events = boardRuntimeEvents()
        storage.runtimeOwners[board.id] = self
        if let runtime = runtimes[board.id] {
            runtime.updateOwner(sheetNavigationActions: actions, events: events)
            if let webExtensionHost, let webExtensionWindow {
                webExtensionHost.register(runtime: runtime, in: webExtensionWindow)
            }
            return runtime
        }

        let runtime = BoardRuntime(
            board: board,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation,
            webExtensionHost: webExtensionHost,
            webExtensionWindow: webExtensionWindow,
            sheetScale: preferences.sheetScale,
            nativePictureInPictureEnabled: preferences.nativePictureInPictureEnabled,
            sheetNavigationActions: actions,
            events: events
        )
        runtimes[board.id] = runtime
        return runtime
    }

    func terminalRuntime(for board: BoardState) -> TerminalRuntime {
        precondition(board.isTerminal, "Web Board cannot create a terminal runtime")
        let events = terminalRuntimeEvents(for: board)
        storage.runtimeOwners[board.id] = self
        if let runtime = terminalRuntimes[board.id] {
            runtime.updateOwner(events: events)
            return runtime
        }

        let command: String?
        if board.isZellij {
            command = zellijClient.launchCommand(sessionName: board.zellijSessionName)
        } else if board.isZmx {
            command = board.zmxSessionName.flatMap {
                zmxClient.launchCommand(
                    sessionName: $0,
                    rootSessionName: board.zmxRootSessionName)
            }
        } else {
            command = nil
        }

        let runtime = TerminalRuntime(
            workingDirectory: board.terminalWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
            command: command,
            events: events)
        terminalRuntimes[board.id] = runtime
        return runtime
    }

    private func sheetNavigationActions(for board: BoardState) -> SheetNavigationManager.Actions {
        .init(
            onOpenBoard: { [weak self] url in
                self?.addBoard(urlString: url.absoluteString, preferredWidth: board.width, afterBoardID: board.id)
            },
            onOpenBoardInBackground: { [weak self] url in
                self?.addBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    focus: false)
            },
            onKeepInDrawer: { [weak self] url in self?.keepInDrawer(url, opensDrawer: false) },
            onEditCurrentSheet: { [weak self] in
                self?.focusBoard(board.id)
                self?.showEditBoardLinkPanel()
            },
            onOpenCurrentSheetInNewBoard: { [weak self] url in
                self?.focusBoard(board.id)
                self?.showOpenBoardPanel(initialURL: url)
            },
            onPasteURLInNewBoard: { [weak self] url in
                self?.addBoard(urlString: url.absoluteString, preferredWidth: board.width, afterBoardID: board.id)
            },
            onCopyURLSucceeded: { [weak self] in
                self?.showToast("Copied Current Sheet URL.", style: .success)
            },
            onCopyURLFailed: { [weak self] in
                self?.showToast("Could not copy Current Sheet URL.", style: .error)
            },
            onPasteURLFailed: { [weak self] in
                self?.showToast("Clipboard does not contain a supported URL.", style: .warning)
            },
            onOpenBoardPanel: { [weak self] in
                self?.focusBoard(board.id)
                self?.showOpenBoardPanel()
            },
            onShowOverview: { [weak self] in
                self?.focusBoard(board.id)
                self?.showOverview()
            },
            onShowEssentials: { [weak self] in
                self?.focusBoard(board.id)
                self?.showEssentialsPrefix()
            },
            onRemoveBoard: { [weak self] in self?.removeBoard(board.id) },
            onRemoveBoardAndFocusNext: { [weak self] in self?.removeBoard(board.id, focusNext: true) },
            onRestoreBoard: { [weak self] in self?.restoreRecentlyRemovedBoard() },
            onFocusFirstBoard: { [weak self] in self?.focusFirstBoardInDesk(containing: board.id) },
            onFocusLastBoard: { [weak self] in self?.focusLastBoardInDesk(containing: board.id) },
            onFocusPreviousBoard: { [weak self] in
                self?.focusBoard(board.id)
                self?.focusPreviousBoard()
            },
            onFocusNextBoard: { [weak self] in
                self?.focusBoard(board.id)
                self?.focusNextBoard()
            },
            onGoToFirstSheet: { [weak self] in self?.goToFirstSheetInBoard(board.id) },
            onGoToLatestSheet: { [weak self] in self?.goToLatestSheetInBoard(board.id) },
            isSupportedSheetURL: SheetURLPolicy.isSupported,
            onNavigateCurrentSheet: { [weak self] url in
                self?.focusBoard(board.id)
                self?.navigateFocusedBoard(urlString: url.absoluteString)
            })
    }

    private func boardRuntimeEvents() -> BoardRuntime.Events {
        .init(
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
            })
    }

    private func terminalRuntimeEvents(for board: BoardState) -> TerminalRuntime.Events {
        .init(
            onClose: { [weak self] in self?.removeBoard(board.id) },
            onFocus: { [weak self] in
                guard
                    let self,
                    !self.isDenMode,
                    self.temporaryContext == nil,
                    self.focusedBoard?.id == board.id
                else { return }
                self.focusBoard(board.id, exitsDenMode: true)
            },
            onWorkingDirectoryChange: { [weak self] path in
                self?.updateTerminalBoard(boardID: board.id, workingDirectory: path)
            },
            onTitleChange: { [weak self] title in
                self?.updateTerminalBoard(boardID: board.id, title: title)
            },
            onOpenURL: { [weak self] url in
                guard let self, let resolvedURL = URL(string: url), SheetURLPolicy.isSupported(resolvedURL)
                else { return }
                let canonicalURL = SheetURLPolicy.canonicalSheetURL(resolvedURL)
                registerTerminalURL(canonicalURL)
                guard
                    addBoard(
                        urlString: canonicalURL.absoluteString,
                        preferredWidth: board.width,
                        afterBoardID: board.id,
                        focus: false)
                else {
                    cancelTerminalURLRegistration(canonicalURL)
                    return
                }
            },
            onNotification: { [weak self] title, body in
                self?.recordNotification(title: title, body: body, boardID: board.id)
            })
    }

    func applySheetScale(_ scale: Int) {
        for runtime in runtimes.values {
            runtime.webView.pageZoom = CGFloat(scale) / 100
        }
        drawerPreviewRuntime?.webView.pageZoom = CGFloat(scale) / 100
    }

    func releaseRuntimes() {
        releaseWebRuntimes()
        for runtime in terminalRuntimes.values {
            runtime.dispose()
        }
        terminalRuntimes.removeAll()
        storage.runtimeOwners.removeAll()
    }

    func releaseWebRuntimes() {
        for boardID in runtimes.keys {
            storage.runtimeOwners.removeValue(forKey: boardID)
        }
        for runtime in runtimes.values {
            runtime.dispose()
        }
        runtimes.removeAll()
        releaseDrawerPreview()
    }

    func releaseWindowResources() {
        deskFilterCenteringTask?.cancel()
        toastTask?.cancel()
        releaseDrawerPreview()
    }

    func disposeRuntime(for boardID: UUID) {
        storage.runtimeOwners.removeValue(forKey: boardID)
        runtimes.removeValue(forKey: boardID)?.dispose()
        terminalRuntimes.removeValue(forKey: boardID)?.dispose()
    }

    var focusedRuntime: BoardRuntime? {
        guard
            let desk = focusedDesk,
            let focusedBoardID = desk.focusedBoardID,
            let board = desk.boards.first(where: { $0.id == focusedBoardID })
        else { return nil }
        guard !board.isTerminal else { return nil }
        return runtime(for: board)
    }

    var focusedTerminalRuntime: TerminalRuntime? {
        guard let board = focusedBoard, board.isTerminal else { return nil }
        return terminalRuntime(for: board)
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

    private func updateTerminalBoard(
        boardID: UUID,
        workingDirectory: String? = nil,
        title: String? = nil
    ) {
        guard let indices = boardIndices(for: boardID),
            state.desks[indices.desk].boards[indices.board].isTerminal
        else { return }
        var changed = false
        if let workingDirectory, !workingDirectory.isEmpty,
            state.desks[indices.desk].boards[indices.board].terminalWorkingDirectory != workingDirectory
        {
            state.desks[indices.desk].boards[indices.board].terminalWorkingDirectory = workingDirectory
            changed = true
        }
        if let title, !title.isEmpty,
            state.desks[indices.desk].boards[indices.board].label != title
        {
            state.desks[indices.desk].boards[indices.board].label = title
            changed = true
        }
        if changed { save() }
    }
}
