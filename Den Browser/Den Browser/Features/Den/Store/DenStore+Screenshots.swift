import AppKit

extension DenStore {
    func captureFocusedSheetScreenshot() {
        guard let board = focusedBoard else {
            showToast("No focused Board.", style: .warning)
            return
        }

        let runtime = runtime(for: board)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let image = try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView)
                let filename = ScreenshotCapture.suggestedFilename(scope: "Current Sheet Screenshot")
                if let destination = try await ScreenshotCapture.savePNG(
                    image,
                    suggestedFilename: filename,
                    attachedTo: runtime.webView.window)
                {
                    showToast("Saved \(destination.lastPathComponent).", style: .success)
                }
            } catch {
                showToast("Screenshot failed: \(error.localizedDescription)", style: .error)
            }
        }
    }

    func captureFocusedDeskScreenshot() {
        guard let desk = focusedDesk, !desk.boards.isEmpty else {
            showToast("Focused Desk has no Boards.", style: .warning)
            return
        }

        let boards = desk.boards.map { ($0, runtime(for: $0)) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var items: [ScreenshotCapture.DeskItem] = []
                for (board, runtime) in boards {
                    let image = try await ScreenshotCapture.visibleCurrentSheet(in: runtime.webView)
                    items.append(.init(label: board.displayName, image: image))
                }

                let image = try ScreenshotCapture.composeDesk(items)
                let filename = ScreenshotCapture.suggestedFilename(scope: "Desk Screenshot")
                if let destination = try await ScreenshotCapture.savePNG(
                    image,
                    suggestedFilename: filename,
                    attachedTo: boards.first?.1.webView.window)
                {
                    showToast("Saved \(destination.lastPathComponent).", style: .success)
                }
            } catch {
                showToast("Screenshot failed: \(error.localizedDescription)", style: .error)
            }
        }
    }
}
