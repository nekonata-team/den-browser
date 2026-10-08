import AppKit
import Darwin
import DenDomain
import Foundation
import WebKit

private struct TerminalSignalError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension DenStore {
    func webRuntime(for board: BoardState, popupWebView: WKWebView? = nil) -> WebBoardRuntime {
        precondition(board.isWeb, "Only Web Boards can create a web runtime")
        ensureWebExtensionContext()
        let actions = sheetNavigationActions(for: board)
        let events = boardRuntimeEvents(for: board)
        storage.onRuntimeOwnerChange?(board.id, self)
        if let runtime = webRuntimes[board.id] {
            runtime.updateOwner(sheetNavigationActions: actions, events: events)
            if let webExtensionHost, let webExtensionWindow {
                webExtensionHost.register(
                    webView: runtime.webView,
                    in: webExtensionWindow,
                    initialURL: nil
                ) { [weak runtime] url in
                    runtime?.load(url)
                }
            }
            return runtime
        }

        let runtime = WebBoardRuntime(
            board: board,
            websiteDataStore: websiteDataStore,
            sheetNavigation: sheetNavigation,
            webExtensionHost: webExtensionHost,
            webExtensionWindow: webExtensionWindow,
            sheetScale: preferences.sheetScale,
            popupWebView: popupWebView,
            sheetNavigationActions: actions,
            events: events
        )
        webRuntimes[board.id] = runtime
        return runtime
    }

    func terminalRuntime(for board: BoardState) -> TerminalRuntime {
        precondition(board.isTerminal, "Web Board cannot create a terminal runtime")
        let events = terminalRuntimeEvents(for: board)
        storage.onRuntimeOwnerChange?(board.id, self)
        if let runtime = terminalRuntimes[board.id] {
            runtime.updateOwner(events: events)
            return runtime
        }

        let command = TerminalLaunchCommand.make(
            for: board.kind,
            zellijClient: zellijClient,
            zmxClient: zmxClient)

        let runtime = TerminalRuntime(
            workingDirectory: board.terminalWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path,
            command: command,
            boardID: board.id,
            profileID: profileID,
            socketPath: ipcSocketPath,
            events: events)
        terminalRuntimes[board.id] = runtime
        return runtime
    }

    private func sheetNavigationActions(for board: BoardState) -> SheetNavigationManager.Actions {
        .init(
            onOpenBoard: { [weak self] url in
                _ = self?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onOpenBoardInBackground: { [weak self] url in
                _ = self?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    focus: false,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onKeepInDrawer: { [weak self] url in self?.keepInDrawer(url, opensDrawer: false) },
            onEditCurrentSheet: { [weak self] in
                self?.focusBoard(board.id)
                self?.onWindowEffect?(.presentEditBoardLink)
            },
            onOpenCurrentSheetInNewBoard: { [weak self] url in
                self?.focusBoard(board.id)
                self?.onWindowEffect?(.presentOpenBoard(initialURL: url, afterBoardID: nil))
            },
            onPasteURLInNewBoard: { [weak self] url in
                _ = self?.createBoard(
                    urlString: url.absoluteString,
                    preferredWidth: board.width,
                    afterBoardID: board.id,
                    recentItem: .url(WebURLPolicy.canonicalSheetURL(url)))
            },
            onCopyURLSucceeded: { [weak self] in
                self?.reportFeedback("Copied Current Sheet URL.", severity: .success)
            },
            onCopyURLFailed: { [weak self] in
                self?.reportFeedback("Could not copy Current Sheet URL.", severity: .error)
            },
            onCopyMarkdownLinkSucceeded: { [weak self] in
                self?.reportFeedback("Copied Current Sheet Markdown link.", severity: .success)
            },
            onCopyMarkdownLinkFailed: { [weak self] in
                self?.reportFeedback("Could not copy Current Sheet Markdown link.", severity: .error)
            },
            onCopyBoardID: { [weak self] in
                self?.copyBoardID(board.id)
            },
            onPasteURLFailed: { [weak self] in
                self?.reportFeedback("Clipboard does not contain a supported URL.", severity: .warning)
            },
            onOpenBoardPanel: { [weak self] in
                self?.focusBoard(board.id)
                self?.onWindowEffect?(.presentOpenBoard(initialURL: nil, afterBoardID: nil))
            },
            onShowOverview: { [weak self] in
                self?.focusBoard(board.id)
                self?.onWindowEffect?(
                    .presentOverview(deskID: self?.presentedDeskID, boardID: self?.focusedDesk?.focusedBoardID))
            },
            onShowEssentials: { [weak self] in
                self?.focusBoard(board.id)
                self?.onWindowEffect?(.presentEssentialsPrefix)
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
            isSupportedSheetURL: WebURLPolicy.isSupported,
            onNavigateCurrentSheet: { [weak self] url in
                self?.focusBoard(board.id)
                self?.navigateFocusedBoard(urlString: url.absoluteString)
            })
    }

    private func boardRuntimeEvents(for board: BoardState) -> WebBoardRuntime.Events {
        .init(
            onChange: { [weak self] boardID, url, title in
                self?.updateBoard(boardID: boardID, url: url, title: title)
            },
            onFullscreenChange: { [weak self] boardID, isFullscreen in
                self?.updateFullscreenStatus(boardID: boardID, isFullscreen: isFullscreen)
            },
            onCreatePopupBoard: { [weak self] webView, url, modifierFlags in
                self?.createPopupBoard(
                    webView,
                    requestedURL: url,
                    fromBoardID: board.id,
                    modifierFlags: modifierFlags) ?? false
            },
            onClosePopupBoard: { [weak self] in
                self?.removeBoard(board.id)
            },
            onLinkActivated: { [weak self] in
                self?.prepareBoardLinkFocus(board.id)
            },
            downloadActivityOwnerID: ObjectIdentifier(self),
            onDownloadActivity: { [weak self] event in
                self?.handleDownloadActivity(event)
            },
            onDownloadFinished: { [weak self] filename in
                self?.reportFeedback("Downloaded \(filename).", severity: .success)
            },
            onDownloadFailed: { [weak self] message in
                self?.reportFeedback("Download failed: \(message)", severity: .error)
            },
            onFocus: { [weak self] in
                self?.onWindowEffect?(.runtimeFocusedBoard(board.id))
            },
            isFocused: { [weak self] in
                self?.focusedDesk?.focusedBoardID == board.id
            },
            restoreFocusedFirstResponder: { [weak self] in
                self?.restoreFocusedFirstResponder()
            })
    }

    func restoreFocusedFirstResponder() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let target: NSView?
            if let webView = self.focusedWebRuntime?.webView {
                target = webView
            } else {
                target = self.focusedTerminalRuntime?.terminalView
            }
            guard let target, let window = target.window,
                needsFirstResponderActivation(window.firstResponder, target: target)
            else { return }
            _ = window.makeFirstResponder(target)
        }
    }

    private func terminalRuntimeEvents(for board: BoardState) -> TerminalRuntime.Events {
        .init(
            onClose: { [weak self] in self?.removeBoard(board.id) },
            onFocus: { [weak self] in
                self?.onWindowEffect?(.runtimeFocusedBoard(board.id))
            },
            onWorkingDirectoryChange: { [weak self] path in
                self?.updateTerminalBoard(boardID: board.id, workingDirectory: path)
            },
            onTitleChange: { [weak self] title in
                self?.updateTerminalBoard(boardID: board.id, title: title)
            },
            onOpenURL: { [weak self] url in
                self?.handleTerminalURL(url, boardID: board.id)
            },
            onNotification: { [weak self] title, body in
                self?.recordNotification(title: title, body: body, boardID: board.id)
            })
    }

    func handleTerminalURL(_ rawURL: String, boardID: BoardID) {
        guard
            let board = board(for: boardID),
            let link = TerminalLinkResolver.resolve(
                rawURL,
                relativeTo: board.terminalWorkingDirectory
                    ?? FileManager.default.homeDirectoryForCurrentUser.path)
        else { return }

        switch link {
        case .localFile(let fileURL):
            _ = NSWorkspace.shared.open(fileURL)
        case .web(let resolvedURL):
            _ = createBoard(
                urlString: resolvedURL.absoluteString,
                preferredWidth: board.width,
                afterBoardID: board.id,
                focus: true,
                recentItem: .url(resolvedURL))
        }
    }

    func applySheetScale(_ scale: Int) {
        for runtime in webRuntimes.values {
            runtime.webView.magnification = 1
            runtime.webView.pageZoom = CGFloat(scale) / 100
        }
        drawerPreviewRuntime?.webView.magnification = 1
        drawerPreviewRuntime?.webView.pageZoom = CGFloat(scale) / 100
    }

    func adjustFocusedSheetSize(by delta: Int) {
        guard let board = focusedBoard, delta != 0 else { return }
        if board.isTerminal {
            terminalRuntime(for: board).adjustFontSize(by: delta)
            return
        }
        guard board.isWeb else { return }

        let webView = webRuntime(for: board).webView
        webView.magnification = 1
        let currentScale = Int((webView.pageZoom * 100).rounded())
        let scale = min(
            max(currentScale + delta * 10, AppPreferences.sheetScaleRange.lowerBound),
            AppPreferences.sheetScaleRange.upperBound
        )
        webView.pageZoom = CGFloat(scale) / 100
    }

    func resetFocusedSheetSize() {
        guard let board = focusedBoard else { return }
        if board.isTerminal {
            terminalRuntime(for: board).resetFontSize()
            return
        }
        guard board.isWeb else { return }

        let webView = webRuntime(for: board).webView
        webView.magnification = 1
        webView.pageZoom = CGFloat(preferences.sheetScale) / 100
    }

    func releaseRuntimes() {
        releaseWebRuntimes()
        for (boardID, runtime) in terminalRuntimes {
            storage.onRuntimeOwnerChange?(boardID, nil)
            runtime.dispose()
        }
        terminalRuntimes.removeAll()
    }

    func releaseWebRuntimes() {
        for (boardID, runtime) in webRuntimes {
            storage.onRuntimeOwnerChange?(boardID, nil)
            runtime.dispose()
        }
        webRuntimes.removeAll()
        releaseDrawerPreview()
    }

    func releaseWindowResources() {
        zmxCommandTask?.cancel()
        zmxCommandTask = nil
        screenshotTask?.cancel()
        screenshotTask = nil
        releaseDrawerPreview()
    }

    func disposeRuntime(for boardID: BoardID) {
        storage.onRuntimeOwnerChange?(boardID, nil)
        webRuntimes.removeValue(forKey: boardID)?.dispose()
        terminalRuntimes.removeValue(forKey: boardID)?.dispose()
    }

    var focusedWebRuntime: WebBoardRuntime? {
        guard
            let desk = focusedDesk,
            let focusedBoardID = desk.focusedBoardID,
            let board = desk.boards.first(where: { $0.id == focusedBoardID })
        else { return nil }
        guard board.isWeb else { return nil }
        return webRuntime(for: board)
    }

    var focusedTerminalRuntime: TerminalRuntime? {
        guard let board = focusedBoard, board.isTerminal else { return nil }
        return terminalRuntime(for: board)
    }

    func updateBoard(boardID: BoardID, url: URL?, title: String?) {
        guard let indices = boardIndices(for: boardID) else { return }
        let board = state.desks[indices.desk].boards[indices.board]
        var changed = false
        if let url, WebURLPolicy.isSupported(url) {
            let canonicalURL = WebURLPolicy.canonicalSheetURL(url)
            if state.desks[indices.desk].boards[indices.board].currentSheetURL != canonicalURL {
                state.desks[indices.desk].boards[indices.board].currentSheetURL = canonicalURL
                changed = true
            }
        }
        if let title, !title.isEmpty, state.desks[indices.desk].boards[indices.board].label != title {
            state.desks[indices.desk].boards[indices.board].label = title
        }
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty,
            let firstSheetURL = board.firstSheetURL
        {
            updateRecentItemTitle(for: firstSheetURL, title: title)
        }
        if changed {
            save()
        }
    }

    private func updateRecentItemTitle(for url: URL, title: String) {
        guard
            let index = recentItems.firstIndex(of: .url(url)),
            case .url(let recentURL, nil) = recentItems[index]
        else { return }
        let original = recentItems
        recentItems[index] = .url(recentURL, title: title)
        if saveStateAndRecentItems() == false {
            recentItems = original
        }
    }

    private func updateTerminalBoard(
        boardID: BoardID,
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
        }
        if changed { save() }
    }

    func foregroundProcessGroupID(for board: BoardState) async throws -> pid_t? {
        guard board.isTerminal else { return nil }
        if board.isZmx, let sessionName = board.zmxSessionName {
            return try await zmxClient.foregroundProcessGroupID(for: sessionName)
        }
        return terminalRuntimes[board.id]?.foregroundProcessGroupID
    }

    func sendSignal(_ signal: Int32, to board: BoardState) async throws -> pid_t {
        guard let pid = try await foregroundProcessGroupID(for: board), pid > 1, pid != getpid() else {
            throw TerminalSignalError(message: "No foreground process found to signal")
        }
        if killpg(pid, signal) == 0 || kill(pid, signal) == 0 {
            return pid
        }
        let err = String(cString: strerror(errno))
        throw TerminalSignalError(message: "Failed to send signal \(signal) to process \(pid): \(err)")
    }
}
