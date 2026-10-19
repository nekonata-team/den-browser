import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
    func quitFocusedBoard() {
        guard let sessionName = focusedBoard?.zmxSessionName else {
            removeFocusedBoard()
            return
        }
        onWindowEffect?(.requestConfirmation(.endZmxSession(sessionName)))
    }

    func endZmxSession(_ sessionName: String) {
        let client = zmxClient
        zmxCommandTask?.cancel()
        zmxCommandTask = Task { [weak self, client] in
            do {
                try await client.killSession(sessionName)
                guard !Task.isCancelled, let self else { return }
                let boardIDs = self.state.desks.flatMap(\.boards)
                    .filter { $0.zmxSessionName == sessionName }.map(\.id)
                for boardID in boardIDs {
                    self.removeBoard(boardID)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.reportFeedback(
                    "Could not end zmx Session '\(sessionName)': \(error.localizedDescription)", severity: .error)
            }
        }
    }

    func canPresentZmxSessions() -> Bool {
        guard zmxClient.isConfigured else {
            reportFeedback("Set an absolute zmx executable path in Settings > Terminal.", severity: .warning)
            return false
        }
        return true
    }

    func openZmxSession(
        _ sessionName: String,
        preferredWidth: Double?,
        rootSessionName: (String) -> String?,
        opensFromOpenBoardPanel: Bool
    ) -> ZmxSessionOpenResult {
        if let board = state.desks.lazy.flatMap(\.boards).first(where: { $0.zmxSessionName == sessionName }) {
            updateZmxRootSessionName(boardID: board.id, rootSessionName: rootSessionName(sessionName))
            focusBoard(board.id, exitsDenMode: true)
            return .focusedExistingBoard
        }
        let trimmed = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected }
        return openBoard(
            input: ":zmx \(trimmed)",
            preferredWidth: preferredWidth,
            opensFromOpenBoardPanel: opensFromOpenBoardPanel,
            zmxRootSessionName: rootSessionName(trimmed))
            ? .openedBoard : .rejected
    }
}
