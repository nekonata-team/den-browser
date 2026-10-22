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
        let operations = zmxBoards
        let client = zmxClient
        let window = zmxWindowProvider()
        let notify = zmxBoardNotifications()
        zmxCommandTask?.cancel()
        zmxCommandTask = Task {
            await operations.end(sessionName, client: client, window: window, notify: notify)
        }
    }

    var zmxBoards: ZmxBoards {
        ZmxBoards(
            state: storage.data, creation: storage.boardCreation, removal: storage.boardRemoval,
            updates: storage.boardUpdates)
    }

    func zmxWindowProvider() -> () -> ZmxBoards.Window? {
        { [weak self] in
            guard let self else { return nil }
            return .init(presentedDeskID: presentedDeskID, focusedBoardID: focusedBoard?.id)
        }
    }

    func zmxBoardNotifications(returnsToOpenBoard: Bool = false) -> (ZmxBoards.Notice) -> Void {
        { [weak self] notice in
            guard let self else { return }
            switch notice {
            case .creation(let notice): boardCreationNotifications(returnsToOpenBoard: returnsToOpenBoard)(notice)
            case .removal(let notice): boardRemovalNotifications()(notice)
            case .duplicationPanel(let root): onWindowEffect?(.presentZmxDuplicationPanel(rootSessionName: root))
            case .warning(let message): reportFeedback(message, severity: .warning)
            case .error(let message): reportFeedback(message, severity: .error)
            case .focusExisting(let id): focusBoard(id, exitsDenMode: true)
            case .openFailure(let message): onWindowEffect?(.openBoardResult(message))
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
        zmxBoards.open(
            sessionName,
            request: inputOpeningContext(preferredWidth: preferredWidth),
            rootSessionName: rootSessionName,
            notify: zmxBoardNotifications(returnsToOpenBoard: opensFromOpenBoardPanel))
    }
}
