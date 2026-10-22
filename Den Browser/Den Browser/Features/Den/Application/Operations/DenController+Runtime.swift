import AppKit
import Darwin
import DenApplication
import DenDomain
import DenPresentationModels
import DenViews
import Foundation
import WebKit

private struct TerminalSignalError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension DenController {
    func runtimeReceiver(for board: BoardState) -> BoardRuntimeReceiver {
        if let receiver = storage.boardRuntimes.receivers[board.id] { return receiver }
        let receiver = BoardRuntimeReceiver(storage: storage, boardID: board.id)
        storage.boardRuntimes.receivers[board.id] = receiver
        return receiver
    }

    func webRuntime(for board: BoardState, popupWebView: WKWebView? = nil) -> WebRuntime {
        precondition(board.isWeb, "Only Web Boards can create a web runtime")
        ensureWebExtensionContext()
        let receiver = runtimeReceiver(for: board)
        let actions = receiver.sheetNavigationActions(for: board, connection: runtimeConnection)
        let events = receiver.webEvents(for: board, connection: runtimeConnection)
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

        let runtime = WebRuntime(
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

    func attachWebRuntime(_ runtime: WebRuntime, to board: BoardState) {
        let receiver = runtimeReceiver(for: board)
        runtime.attach(
            to: board,
            sheetNavigationActions: receiver.sheetNavigationActions(for: board, connection: runtimeConnection),
            events: receiver.webEvents(for: board, connection: runtimeConnection))
        webRuntimes[board.id] = runtime
        runtime.activateWebExtensionTab()
    }

    func terminalRuntime(for board: BoardState) -> TerminalRuntime {
        precondition(board.isTerminal, "Web Board cannot create a terminal runtime")
        let events = runtimeReceiver(for: board).terminalEvents(for: board, connection: runtimeConnection)
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
        drawerPeekRuntime?.webView.magnification = 1
        drawerPeekRuntime?.webView.pageZoom = CGFloat(scale) / 100
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
        storage.facingCache.removeAll()
        releaseWebRuntimes()
        storage.boardRuntimes.releaseTerminal()
    }

    func releaseWebRuntimes() {
        storage.boardRuntimes.releaseWeb()
        releaseDrawerPeek()
    }

    func releaseWindowResources() {
        cancelWindowOperationTasks()
        releaseDrawerPeek()
    }

    func disposeRuntime(for boardID: BoardID) {
        storage.facingCache.invalidate(for: boardID)
        storage.boardRuntimes.dispose(boardID)
    }

    var focusedWebRuntime: WebRuntime? {
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
        storage.boardUpdates.updateWeb(boardID, url: url, title: title, recents: storage.recents) {
            storage.facingCache.invalidate(for: boardID)
        }
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
