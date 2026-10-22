import DenDomain
import Foundation

@MainActor
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

    private let store: DenStateStore
    private let creation: BoardCreation
    private let items: DrawerItems

    public init(store: DenStateStore, creation: BoardCreation, items: DrawerItems) {
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
        guard let item = store.snapshot.den.drawerItems.first(where: { $0.id == request.itemID }),
            let boardID = creation.createWeb(
                urlString: item.url.absoluteString, width: request.width, searchEngine: request.searchEngine,
                target: request.target,
                recentItem: .url(WebURLPolicy.canonicalSheetURL(item.url)), notify: notifyBoard)
        else { return nil }
        items.consume(request.itemID, notify: notifyDrawer)
        return boardID
    }
}
