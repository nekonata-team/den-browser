import AppKit

private enum ScreenshotDestination {
    case save(scope: String, window: NSWindow?)
    case clipboard
}

private enum ScreenshotResult {
    case saved(URL)
    case copied
}

extension DenStore {
    func captureFocusedSheetScreenshot() {
        guard let runtime = focusedSheetRuntime() else { return }
        startScreenshotTask(
            capture: { try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView) },
            destination: .save(
                scope: "Current Sheet Screenshot",
                window: runtime.webView.window),
            successMessage: { result in
                guard case let .saved(destination) = result else { return "" }
                return "Saved \(destination.lastPathComponent)."
            })
    }

    func captureFocusedDeskScreenshot() {
        guard let boards = focusedDeskRuntimes() else { return }
        startScreenshotTask(
            capture: {
                let items = try await Self.captureDeskItems(for: boards)
                return try ScreenshotCapture.composeDesk(items)
            },
            destination: .save(
                scope: "Desk Screenshot",
                window: boards.first?.1.webView.window),
            successMessage: { result in
                guard case let .saved(destination) = result else { return "" }
                return "Saved \(destination.lastPathComponent)."
            })
    }

    func copyFocusedSheetScreenshot() {
        guard let runtime = focusedSheetRuntime() else { return }
        startScreenshotTask(
            capture: { try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView) },
            destination: .clipboard,
            successMessage: { _ in "Copied Current Sheet screenshot to clipboard." })
    }

    func copyFocusedDeskScreenshot() {
        guard let boards = focusedDeskRuntimes() else { return }
        startScreenshotTask(
            capture: {
                let items = try await Self.captureDeskItems(for: boards)
                return try ScreenshotCapture.composeDesk(items)
            },
            destination: .clipboard,
            successMessage: { _ in "Copied Focused Desk screenshot to clipboard." })
    }

    private func focusedSheetRuntime() -> BoardRuntime? {
        guard let board = focusedBoard, !board.isTerminal else {
            showToast("No focused Board.", style: .warning)
            return nil
        }
        return runtime(for: board)
    }

    private func focusedDeskRuntimes() -> [(BoardState, BoardRuntime)]? {
        guard let desk = focusedDesk, !desk.boards.isEmpty else {
            showToast("Focused Desk has no Boards.", style: .warning)
            return nil
        }
        guard !desk.boards.contains(where: \.isTerminal) else {
            showToast("Desk screenshots do not support Terminal Boards.", style: .warning)
            return nil
        }
        return desk.boards.map { ($0, runtime(for: $0)) }
    }

    private func startScreenshotTask(
        capture: @escaping @MainActor () async throws -> NSImage,
        destination: ScreenshotDestination,
        successMessage: @escaping @MainActor (ScreenshotResult) -> String
    ) {
        screenshotTask?.cancel()
        screenshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.screenshotTask = nil }

            do {
                let image = try await capture()
                guard !Task.isCancelled else { return }

                let result: ScreenshotResult
                switch destination {
                case let .save(scope, window):
                    let filename = ScreenshotOutput.suggestedFilename(scope: scope)
                    guard
                        let destination = try await ScreenshotOutput.savePNG(
                            image,
                            suggestedFilename: filename,
                            attachedTo: window)
                    else { return }
                    result = .saved(destination)
                case .clipboard:
                    try ScreenshotOutput.copyPNG(image)
                    result = .copied
                }

                guard !Task.isCancelled else { return }
                showToast(successMessage(result), style: .success)
            } catch is CancellationError {
                return
            } catch {
                showToast("Screenshot failed: \(error.localizedDescription)", style: .error)
            }
        }
    }

    private static func captureDeskItems(
        for boards: [(BoardState, BoardRuntime)]
    ) async throws -> [ScreenshotCapture.DeskItem] {
        var items: [ScreenshotCapture.DeskItem] = []
        for (board, runtime) in boards {
            let image = try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView)
            items.append(.init(label: board.displayName, image: image))
        }
        return items
    }
}
