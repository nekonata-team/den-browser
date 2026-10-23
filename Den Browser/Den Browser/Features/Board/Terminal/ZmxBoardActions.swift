import DenApplication
import DenDomain
import DenModels
import DenViews
import Foundation

@MainActor
final class ZmxBoardActions {
    private let context: WindowNativeContext
    private let boardNavigation: BoardNavigation
    private let boardRemoval: BoardRemovalPresentation
    private let boardOpening: BoardOpeningActions
    private var storage: DenProfileResources { context.storage }
    private var state: DenState { context.storage.state }
    private var focusedBoard: BoardState? { context.focusedBoard }
    private var presentedDeskID: DeskID { context.navigation.presentedDeskID }
    private var zmxClient: ZmxClient { context.zmxClient }
    private var onWindowEffect: ((DenWindowEffect) -> Void)? { context.connection.onWindowEffect }
    private var zmxCommandTask: Task<Void, Never>? {
        get { context.windowResources.zmxCommandTask }
        set { context.windowResources.zmxCommandTask = newValue }
    }

    init(
        context: WindowNativeContext, boardNavigation: BoardNavigation, boardRemoval: BoardRemovalPresentation,
        boardOpening: BoardOpeningActions
    ) {
        self.context = context
        self.boardNavigation = boardNavigation
        self.boardRemoval = boardRemoval
        self.boardOpening = boardOpening
    }

    func quitFocusedBoard() {
        guard let sessionName = focusedBoard?.zmxSessionName else {
            boardRemoval.removeFocusedBoard()
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
            case .creation(let notice):
                boardOpening.boardCreationNotifications(returnsToOpenBoard: returnsToOpenBoard)(notice)
            case .removal(let notice): boardRemoval.boardRemovalNotifications()(notice)
            case .duplicationPanel(let root): onWindowEffect?(.presentZmxDuplicationPanel(rootSessionName: root))
            case .warning(let message): context.feedback.publish(message, severity: .warning)
            case .error(let message): context.feedback.publish(message, severity: .error)
            case .focusExisting(let id): boardNavigation.focusBoard(id, exitsDenMode: true)
            case .openFailure(let message): onWindowEffect?(.openBoardResult(message))
            }
        }
    }

    func canPresentZmxSessions() -> Bool {
        guard zmxClient.isConfigured else {
            context.feedback.publish("Set an absolute zmx executable path in Settings > Terminal.", severity: .warning)
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
            request: boardOpening.inputOpeningContext(preferredWidth: preferredWidth),
            rootSessionName: rootSessionName,
            notify: zmxBoardNotifications(returnsToOpenBoard: opensFromOpenBoardPanel))
    }

    func duplicateFocusedBoard() {
        guard let source = focusedBoard else { return }
        switch BoardDuplication.resolve(source) {
        case .create(let board):
            boardOpening.insertBoard(board, afterBoardID: source.id, focus: true, origin: .interactive)
        case .zmxSession:
            presentZmxDuplicationPanel(for: source)
        case .unavailable:
            break
        }
    }

    private func presentZmxDuplicationPanel(for source: BoardState) {
        let operations = zmxBoards
        let client = zmxClient
        let window = zmxWindowProvider()
        let notify = zmxBoardNotifications()
        zmxCommandTask?.cancel()
        zmxCommandTask = Task {
            await operations.prepareDuplication(source, client: client, window: window, notify: notify)
        }
    }

    func duplicateFocusedZmxBoard(suffix: String) {
        guard let source = focusedBoard else { return }
        createZmxBoard(from: source, suffix: suffix, asSideBoard: false, focus: true)
    }

    func createZmxBoard(from source: BoardState, suffix: String, asSideBoard: Bool, focus: Bool) {
        guard source.zmxSessionName != nil else { return }
        let request = ZmxBoards.Duplication(
            source: source, suffix: suffix, asSideBoard: asSideBoard, focus: focus,
            width: asSideBoard ? DenLayout.sideBoardInitialWidth : source.width,
            workingDirectory: source.terminalWorkingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path)
        let operations = zmxBoards
        let client = zmxClient
        let window = zmxWindowProvider()
        let notify = zmxBoardNotifications()
        zmxCommandTask?.cancel()
        zmxCommandTask = Task {
            await operations.duplicate(request, client: client, window: window, notify: notify)
        }
    }

    func cancelZmxDuplicationRequest() {
        zmxCommandTask?.cancel()
        zmxCommandTask = nil
    }

    func waitForZmxCommand() async {
        await zmxCommandTask?.value
    }

    func duplicateFocusedBoardFromFirstSheet() {
        guard let source = focusedBoard else { return }
        switch BoardDuplication.resolve(source, fromFirstSheet: true) {
        case .create(let board):
            boardOpening.insertBoard(board, afterBoardID: source.id, focus: true, origin: .interactive)
        case .zmxSession:
            duplicateFocusedZmxBoard(suffix: "")
        case .unavailable:
            break
        }
    }
}
