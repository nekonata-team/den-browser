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

    private let reader: DenStateReader
    private let writer: DenStateWriter
    private let creation: BoardCreation
    private let items: DrawerItems

    public init(reader: DenStateReader, writer: DenStateWriter, creation: BoardCreation, items: DrawerItems) {
        self.reader = reader
        self.writer = writer
        self.creation = creation
        self.items = items
    }

    /// Consume the source item only after the destination Board has been created successfully.
    @discardableResult
    public func place(
        _ request: Request,
        notifyBoard: (BoardCreation.Notice) -> Void,
        notifyDrawer: (DrawerItems.Notice) -> Void
    ) -> BoardID? {
        guard let index = reader.snapshot.den.drawerItems.firstIndex(where: { $0.id == request.itemID }) else {
            return nil
        }
        let item = reader.snapshot.den.drawerItems[index]
        let boardID: BoardID?
        switch item.content {
        case .web(let url):
            boardID = creation.insert(
                BoardState(id: BoardID(item.id), label: item.displayName, width: request.width, currentSheetURL: url),
                target: request.target,
                recentItem: .url(WebURLPolicy.canonicalSheetURL(url)),
                notify: notifyBoard
            )
        case .terminal(let session):
            let recent: RecentItem =
                switch session {
                case .shell(let directory): .terminal(workingDirectory: directory)
                case .zellij(let zellij): .zellij(sessionName: zellij.sessionName)
                case .zmx(let zmx): .zmx(sessionName: zmx.sessionName)
                }
            boardID = creation.insert(
                BoardState(id: BoardID(item.id), label: item.displayName, width: request.width, terminal: session),
                target: request.target,
                recentItem: recent,
                notify: notifyBoard
            )
        }
        guard let boardID else { return nil }
        items.consume(request.itemID, notify: notifyDrawer)
        writer.update { $0.rememberBoardOperation(.placedFromDrawer(itemID: item.id, sourceIndex: index)) }
        return boardID
    }
}
