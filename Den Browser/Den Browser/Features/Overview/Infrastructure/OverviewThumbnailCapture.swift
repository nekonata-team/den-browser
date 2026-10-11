import AppKit
import DenDomain
import Foundation
import GhosttyTerminal
import WebKit

@MainActor
final class OverviewThumbnailCapture {
    // Suppression duration: do not recapture same board within 30 seconds
    static let recaptureSuppressionDuration: Duration = .seconds(30)
    // Cap both dimensions without changing the Board's aspect ratio.
    static let maxCapturePixels: CGFloat = 720

    private let cache: OverviewThumbnailCache

    init(cache: OverviewThumbnailCache) {
        self.cache = cache
    }

    func shouldCapture(boardID: BoardID) -> Bool {
        if cache.isCapturing(boardID) {
            return false
        }
        if let lastCaptured = cache.lastCapturedInstant(for: boardID) {
            let elapsed = ContinuousClock.now - lastCaptured
            if elapsed < Self.recaptureSuppressionDuration {
                return false
            }
        }
        return true
    }

    func captureWeb(boardID: BoardID, webView: WKWebView) async {
        guard shouldCapture(boardID: boardID) else { return }
        guard !Task.isCancelled, let url = webView.url, !webView.isLoading else { return }

        let token = cache.beginCapture(for: boardID)
        defer { cache.finishCapture(token, for: boardID) }

        let bounds = webView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let backingScale = webView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let captureWidth =
            bounds.width * min(1, Self.maxCapturePixels / (max(bounds.width, bounds.height) * backingScale))
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(captureWidth))
        config.afterScreenUpdates = true

        do {
            let image = try await webView.takeSnapshot(configuration: config)
            guard !Task.isCancelled, webView.url == url, !webView.isLoading else { return }
            cache.setCapturedThumbnail(image, for: boardID, token: token)
        } catch {
            // Keep existing thumbnail on failure
        }
    }

    func captureTerminal(boardID: BoardID, terminalView: AppTerminalView) {
        guard shouldCapture(boardID: boardID) else { return }
        guard terminalView.window != nil, !terminalView.isHiddenOrHasHiddenAncestor else { return }

        guard
            let image = try? ScreenshotCapture.visibleCurrentSheet(
                in: terminalView,
                maxPixels: Self.maxCapturePixels
            )
        else {
            return
        }

        let token = cache.beginCapture(for: boardID)
        // Capture before hiding, but publish outside NSViewRepresentable's update transaction.
        Task { @MainActor in
            defer { cache.finishCapture(token, for: boardID) }
            cache.setCapturedThumbnail(image, for: boardID, token: token)
        }
    }
}
