public import DenDomain
import Foundation

public struct DrawerPlacement {
    public struct Request {
        public let itemID: UUID
        public let width: Double
        public let searchEngine: SearchEngine
        public let target: BoardCreation.Target

        public init(itemID: UUID, width: Double, searchEngine: SearchEngine, target: BoardCreation.Target) {
            self.itemID = itemID
            self.width = width
            self.searchEngine = searchEngine
            self.target = target
        }
    }

    private let store: DenStateReader
    private let creation: BoardCreation
    private let items: DrawerItems

    public init(store: DenStateReader, creation: BoardCreation, items: DrawerItems) {
        self.store = store
        self.creation = creation
        self.items = items
    }

    /// Consume the source item only after the destination Board has been created successfully.
    @discardableResult
    public func place(
        _ request: Request,
        notifyBoard: (BoardCreation.Notice) -> Void, notifyDrawer: (DrawerItems.Notice) -> Void
    ) -> BoardID? {
        guard let item = store.snapshot.den.drawerItems.first(where: { $0.id == request.itemID }) else { return nil }
        let boardID: BoardID?
        switch item.content {
        case .web(let url):
            boardID = creation.createWeb(
                urlString: url.absoluteString, width: request.width, searchEngine: request.searchEngine,
                target: request.target, recentItem: .url(WebURLPolicy.canonicalSheetURL(url)), notify: notifyBoard)
        case .terminal(let session):
            let recent: RecentItem =
                switch session {
                case .shell(let directory): .terminal(workingDirectory: directory)
                case .zellij(let zellij): .zellij(sessionName: zellij.sessionName)
                case .zmx(let zmx): .zmx(sessionName: zmx.sessionName)
                }
            boardID = creation.insert(
                BoardState(id: BoardID(item.id), label: item.displayName, width: request.width, terminal: session),
                target: request.target, recentItem: recent, notify: notifyBoard)
        }
        guard let boardID else { return nil }
        items.consume(request.itemID, notify: notifyDrawer)
        return boardID
    }
}
