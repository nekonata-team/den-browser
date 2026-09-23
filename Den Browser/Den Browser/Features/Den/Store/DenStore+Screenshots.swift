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

    func copyFocusedSheetScreenshot() {
        guard let runtime = focusedSheetRuntime() else { return }
        startScreenshotTask(
            capture: { try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView) },
            destination: .clipboard,
            successMessage: { _ in "Copied Current Sheet screenshot to clipboard." })
    }

    private func focusedSheetRuntime() -> BoardRuntime? {
        guard let board = focusedBoard, !board.isTerminal else {
            showToast("No focused Board.", style: .warning)
            return nil
        }
        return runtime(for: board)
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

}
