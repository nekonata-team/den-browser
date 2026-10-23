import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import WebKit

@MainActor
final class DeskFacings {
    private let context: WindowNativeContext
    private var focusedDesk: DeskState? { context.focusedDesk }
    private var facingCache: BoardFacingCache { context.storage.facingCache }
    private var facingCapture: BoardFacingCapture { context.storage.facingCapture }
    private var presetFacingStore: PresetFacingStore { context.storage.presetFacingStore }
    private var canCaptureFacing: Bool { context.storage.activeDrag == nil }
    private var webRuntimes: [BoardID: WebRuntime] {
        get { context.storage.webRuntimes }
        set { context.storage.webRuntimes = newValue }
    }
    private var terminalRuntimes: [BoardID: TerminalRuntime] {
        get { context.storage.terminalRuntimes }
        set { context.storage.terminalRuntimes = newValue }
    }

    init(context: WindowNativeContext) {
        self.context = context
    }

    func savePresetFacings(for presetID: UUID, boards: [BoardState]) {
        for (index, board) in boards.enumerated() {
            if let image = facingCache.image(for: board.id) {
                presetFacingStore.setFacing(image, for: presetID, at: index)
            }
        }
    }

    func captureFocusedDeskFacings() async {
        guard canCaptureFacing, let boards = focusedDesk?.boards else { return }
        for board in boards {
            if let runtime = webRuntimes[board.id], !runtime.webView.isHidden {
                await facingCapture.captureWeb(boardID: board.id, webView: runtime.webView)
            } else if let runtime = terminalRuntimes[board.id], !runtime.terminalView.isHidden {
                facingCapture.captureTerminal(boardID: board.id, terminalView: runtime.terminalView)
            }
            await facingCache.loadFacing(for: board.id)
        }
    }

    func removePresetFacings(for presetID: UUID) {
        presetFacingStore.remove(for: presetID)
    }
}
