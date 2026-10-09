import DenDomain
import Foundation

public enum DrawerPlacement {
    /// Remove the source item only after the destination Board has been created successfully.
    public static func place(
        _ itemID: UUID,
        among items: [DrawerItem],
        createBoard: (DrawerItem) -> BoardID?,
        discardItem: (UUID) -> Void
    ) -> BoardID? {
        guard let item = items.first(where: { $0.id == itemID }),
            let boardID = createBoard(item)
        else { return nil }
        discardItem(itemID)
        return boardID
    }
}
