import AppKit
import DenDomain
import DenPresentationModels

private enum FocusedScreenshotTarget {
    case web(WebRuntime)
    case terminal(TerminalRuntime)

    var window: NSWindow? {
        switch self {
        case .web(let runtime): runtime.webView.window
        case .terminal(let runtime): runtime.terminalView.window
        }
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
        performSheetScreenshot(
            capture: { try await target.capture() },
            destination: .save(window: target.window))
    }

    func copyFocusedSheetScreenshot() {
        guard let target = focusedScreenshotTarget() else { return }
        performSheetScreenshot(capture: { try await target.capture() }, destination: .clipboard)
    }

    private func performSheetScreenshot(
        capture: @escaping @MainActor () async throws -> NSImage,
        destination: ScreenshotOutput.Destination
    ) {
        startScreenshotOperation { [weak self] in
            guard let self else { return }
            do {
                guard
                    let message = try await ScreenshotOutput.captureAndOutput(
                        capture: capture, destination: destination)
                else { return }
                reportFeedback(message, severity: .success)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                reportFeedback("Screenshot failed: \(error.localizedDescription)", severity: .error)
            }
        }
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
}
