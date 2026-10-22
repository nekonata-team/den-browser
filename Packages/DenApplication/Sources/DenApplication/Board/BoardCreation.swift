import DenDomain
import Foundation

@MainActor
public final class BoardCreation {
    public static let maximumRecentItemCount = 500

    public struct Target {
        public let presentedDeskID: DeskID
        public let deskID: DeskID?
        public let afterBoardID: BoardID?
        public let focus: Bool
        public let origin: BoardOperationOrigin

        public init(
            presentedDeskID: DeskID, deskID: DeskID? = nil, afterBoardID: BoardID? = nil,
            focus: Bool = true, origin: BoardOperationOrigin = .interactive
        ) {
            self.presentedDeskID = presentedDeskID
            self.deskID = deskID
            self.afterBoardID = afterBoardID
            self.focus = focus
            self.origin = origin
        }
    }

    public struct OpenRequest {
        public let input: String
        public let width: Double
        public let target: Target
        public let configuration: BoardOpening.Configuration
        public let zmxRootSessionName: String?

        public init(
            input: String, width: Double, target: Target, configuration: BoardOpening.Configuration,
            zmxRootSessionName: String? = nil
        ) {
            self.input = input
            self.width = width
            self.target = target
            self.configuration = configuration
            self.zmxRootSessionName = zmxRootSessionName
        }
    }

    /// Delivers creation notifications synchronously before and after Store mutation.
    public enum Notice {
        case willInsert(BoardState)
        case prepareLinkFocus(BoardID, BoardOperationOrigin)
        case suppressMutationAnimation
        case focusInsertedBoard(DeskID)
        case didInsert(BoardState)
        case focusTutorial(BoardID)
        case didOpenInput
        case selectZmxSession
    }

    private let store: DenStateStore
    private let writer: DenStateWriter
    private let persist: ((DenState) -> Bool)?
    private let persistRecent: (([RecentItem]) -> Bool)?
    private let directoryExists: (String) -> Bool

    public init(
        store: DenStateStore, writer: DenStateWriter,
        persist: ((DenState) -> Bool)? = nil, persistRecent: (([RecentItem]) -> Bool)? = nil,
        directoryExists: @escaping (String) -> Bool
    ) {
        self.store = store
        self.writer = writer
        self.persist = persist
        self.persistRecent = persistRecent
        self.directoryExists = directoryExists
    }

    public func open(_ request: OpenRequest, notify: (Notice) -> Void) -> BoardOpenResult {
        let decision = BoardOpening.resolve(
            input: request.input, width: request.width, zmxRootSessionName: request.zmxRootSessionName,
            configuration: request.configuration, directoryExists: directoryExists)
        switch decision {
        case .createBoard(let board, let recentItem):
            guard insert(board, target: request.target, recentItem: recentItem, notify: notify) != nil else {
                return .rejected(nil)
            }
            notify(.didOpenInput)
            return .accepted
        case .openTutorial:
            return openTutorial(width: request.width, target: request.target, notify: notify) != nil
                ? .accepted : .rejected(nil)
        case .selectZmxSession:
            notify(.selectZmxSession)
            return .accepted
        case .rejected(let failure):
            switch failure {
            case .zmxNotConfigured:
                return .rejected("Set an absolute zmx executable path in Settings > Terminal.")
            case .zellijNotConfigured:
                return .rejected("Set an absolute Zellij executable path in Settings > Terminal.")
            case .terminalDirectoryMissing(let path):
                return .rejected(TerminalInputError.missingDirectory(path).message)
            case .invalidInput:
                return .rejected(nil)
            }
        }
    }

    @discardableResult
    public func openTutorial(width: Double, target: Target, notify: (Notice) -> Void) -> BoardID? {
        if let board = store.snapshot.den.desks.lazy.flatMap(\.boards).first(where: \.isTutorial) {
            notify(.focusTutorial(board.id))
            return board.id
        }
        return insert(BoardState(width: width, tutorial: TutorialBoardState()), target: target, notify: notify)
    }

    @discardableResult
    public func createWeb(
        urlString: String, width: Double, searchEngine: SearchEngine, target: Target,
        recentItem: RecentItem? = nil, notify: (Notice) -> Void
    ) -> BoardID? {
        guard let url = BoardInputResolver.normalizedURL(from: urlString, searchEngine: searchEngine) else {
            return nil
        }
        let board = BoardState(
            label: url.host(percentEncoded: false) ?? url.absoluteString, width: width, currentSheetURL: url)
        return insert(board, target: target, recentItem: recentItem, notify: notify)
    }

    @discardableResult
    public func createTerminal(
        workingDirectory: String, width: Double, target: Target,
        recentItem: RecentItem? = nil, notify: (Notice) -> Void
    ) -> BoardID? {
        insert(
            BoardState(width: width, workingDirectory: workingDirectory),
            target: target, recentItem: recentItem, notify: notify)
    }

    @discardableResult
    public func insert(
        _ board: BoardState, target: Target, recentItem: RecentItem? = nil, notify: (Notice) -> Void
    ) -> BoardID? {
        guard
            let insertion = BoardInsertion.insert(
                board, in: store.snapshot.den.desks, presentedDeskID: target.presentedDeskID,
                deskID: target.deskID, afterBoardID: target.afterBoardID, focus: target.focus)
        else { return nil }

        notify(.willInsert(board))
        if !target.focus, let anchor = insertion.afterBoardID {
            notify(.prepareLinkFocus(anchor, target.origin))
        }
        let deskIndex = insertion.deskIndex.rawValue
        if store.snapshot.den.desks[deskIndex].boards.isEmpty
            || (target.origin == .cli && !target.focus && insertion.afterBoardID != nil)
        {
            notify(.suppressMutationAnimation)
        }
        writer.update { $0.den.desks[deskIndex] = insertion.desk }
        if target.focus { notify(.focusInsertedBoard(insertion.desk.id)) }
        if recentItem == nil { _ = save() }
        notify(.didInsert(board))
        if let recentItem { recordRecent(recentItem) }
        return board.id
    }

    private func save() -> Bool {
        guard store.snapshot.activeDrag == nil else { return false }
        return persist?(store.snapshot.den) ?? false
    }

    private func recordRecent(_ item: RecentItem) {
        let original = store.snapshot.recentItems
        let itemToSave: RecentItem
        if case .url(let url, nil) = item, let title = original.first(where: { $0 == item })?.title {
            itemToSave = .url(url, title: title)
        } else {
            itemToSave = item
        }
        writer.update { snapshot in
            snapshot.recentItems.removeAll { $0 == itemToSave }
            snapshot.recentItems.insert(itemToSave, at: 0)
            if snapshot.recentItems.count > Self.maximumRecentItemCount {
                snapshot.recentItems.removeLast(snapshot.recentItems.count - Self.maximumRecentItemCount)
            }
        }
        let saved = persist != nil ? save() : (persistRecent?(store.snapshot.recentItems) ?? true)
        if !saved { writer.update { $0.recentItems = original } }
    }
}
