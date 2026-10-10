import DenApplication
import DenDomain
import DenPresentationModels
import Foundation

extension DenController {
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
