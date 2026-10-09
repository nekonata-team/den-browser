import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct DrawerPlacementTests {
    @Test func missingItemDoesNotCreateOrDiscardAnything() {
        // Arrange
        var created = false
        var discarded = false

        // Act
        let boardID = DrawerPlacement.place(
            UUID(), among: [],
            createBoard: { _ in
                created = true
                return BoardID()
            },
            discardItem: { _ in discarded = true })

        // Assert
        #expect(boardID == nil)
        #expect(!created)
        #expect(!discarded)
    }

    @Test func failedCreationKeepsTheDrawerItem() {
        // Arrange
        let item = DrawerItem(url: URL(string: "https://example.com/")!)
        var items = [item]

        // Act
        let boardID = DrawerPlacement.place(
            item.id, among: items,
            createBoard: { _ in nil },
            discardItem: { id in items.removeAll { $0.id == id } })

        // Assert
        #expect(boardID == nil)
        #expect(items == [item])
    }

    @Test func successfulCreationTransfersOnlyTheRequestedItem() {
        // Arrange
        let item = DrawerItem(url: URL(string: "https://example.com/")!)
        let other = DrawerItem(url: URL(string: "https://other.example/")!)
        var items = [item, other]
        let createdBoardID = BoardID()
        var createdFrom: DrawerItem?

        // Act
        let boardID = DrawerPlacement.place(
            item.id, among: items,
            createBoard: { source in
                createdFrom = source
                return createdBoardID
            },
            discardItem: { id in items.removeAll { $0.id == id } })

        // Assert
        #expect(boardID == createdBoardID)
        #expect(createdFrom == item)
        #expect(items == [other])
    }
}
