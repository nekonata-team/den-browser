import AppKit
import DenDomain
import DenPresentationModels

private enum ScreenshotDestination {
    case save(scope: String, window: NSWindow?)
    case clipboard
}

private enum ScreenshotResult {
    case saved(URL)
    case copied
}

private enum FocusedScreenshotTarget {
    case web(WebRuntime)
    case terminal(TerminalRuntime)

    var window: NSWindow? {
        switch self {
        case .web(let runtime): runtime.webView.window
        case .terminal(let runtime): runtime.terminalView.window
        }
    }

    var defaultScope: String {
        "Current Sheet Screenshot"
    }

    var clipboardSuccessMessage: String {
        "Copied Current Sheet screenshot to clipboard."
    }

    func capture() async throws -> NSImage {
        switch self {
        case .web(let runtime):
            try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView)
        case .terminal(let runtime):
            try ScreenshotCapture.visibleCurrentSheet(in: runtime.terminalView)
        }
    }
}

extension DenController {
    func captureFocusedSheetScreenshot() {
        guard let target = focusedScreenshotTarget() else { return }
        startScreenshotTask(
            capture: { try await target.capture() },
            destination: .save(
                scope: target.defaultScope,
                window: target.window),
            successMessage: { result in
                guard case let .saved(destination) = result else { return "" }
                return "Saved \(destination.lastPathComponent)."
            })
    }

    func copyFocusedSheetScreenshot() {
        guard let target = focusedScreenshotTarget() else { return }
        startScreenshotTask(
            capture: { try await target.capture() },
            destination: .clipboard,
            successMessage: { _ in target.clipboardSuccessMessage })
    }

    private func focusedScreenshotTarget() -> FocusedScreenshotTarget? {
        guard let board = focusedBoard else {
            reportFeedback("No focused Board.", severity: .warning)
            return nil
        }
        if board.isWeb {
            return .web(webRuntime(for: board))
        }
        if board.isTerminal {
            return .terminal(terminalRuntime(for: board))
        }
        reportFeedback("Focused Board cannot be captured.", severity: .warning)
        return nil
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
                reportFeedback(successMessage(result), severity: .success)
            } catch is CancellationError {
                return
            } catch {
                reportFeedback("Screenshot failed: \(error.localizedDescription)", severity: .error)
            }
        }
    }
}
