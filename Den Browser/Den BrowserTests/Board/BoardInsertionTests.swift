import DenApplication
import DenDomain
import Testing

@MainActor
struct BoardInsertionTests {
    @Test(arguments: [false, true])
    func insertsAfterWholeGroupWhenAnchoredToEitherMember(_ anchorsToSide: Bool) throws {
        // Arrange
        let primary = BoardState(label: "Primary", width: 520, currentSheetURL: nil)
        let side = BoardState(width: 390, targetBoardID: primary.id)
        let tail = BoardState(label: "Tail", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [primary, side, tail], focusedBoardID: primary.id)
        let anchorID = anchorsToSide ? side.id : primary.id

        let inserted = BoardState(label: "Inserted", width: 520, currentSheetURL: nil)

        // Act
        let destination = try #require(
            BoardInsertion.insert(inserted, in: [desk], presentedDeskID: desk.id, afterBoardID: anchorID))

        // Assert
        #expect(destination.deskIndex == 0)
        #expect(destination.desk.boards.map(\.id) == [primary.id, side.id, inserted.id, tail.id])
        #expect(destination.afterBoardID == anchorID)
    }

    @Test func defaultsToPresentedDeskFocusWithoutCreatingExplicitAnchor() throws {
        // Arrange
        let other = DeskState(label: "Other", boards: [])
        let focused = BoardState(label: "Focused", width: 520, currentSheetURL: nil)
        let tail = BoardState(label: "Tail", width: 520, currentSheetURL: nil)
        let presented = DeskState(label: "Presented", boards: [focused, tail], focusedBoardID: focused.id)

        let inserted = BoardState(label: "Inserted", width: 520, currentSheetURL: nil)

        // Act
        let destination = try #require(
            BoardInsertion.insert(inserted, in: [other, presented], presentedDeskID: presented.id))

        // Assert
        #expect(destination.deskIndex == 1)
        #expect(destination.desk.boards.map(\.id) == [focused.id, inserted.id, tail.id])
        #expect(destination.afterBoardID == nil)
    }

    @Test func explicitAnchorSelectsItsOwningDesk() throws {
        // Arrange
        let presented = DeskState(label: "Presented", boards: [])
        let anchor = BoardState(label: "Anchor", width: 520, currentSheetURL: nil)
        let owning = DeskState(label: "Owning", boards: [anchor], focusedBoardID: anchor.id)

        let inserted = BoardState(label: "Inserted", width: 520, currentSheetURL: nil)

        // Act
        let destination = try #require(
            BoardInsertion.insert(
                inserted, in: [presented, owning], presentedDeskID: presented.id, afterBoardID: anchor.id))

        // Assert
        #expect(destination.deskIndex == 1)
        #expect(destination.desk.boards.map(\.id) == [anchor.id, inserted.id])
        #expect(destination.afterBoardID == anchor.id)
    }

    @Test(arguments: [false, true])
    func explicitDeskIgnoresUnusableAnchorAndUsesItsOwnFocus(_ missingAnchor: Bool) throws {
        // Arrange
        let outside = BoardState(label: "Outside", width: 520, currentSheetURL: nil)
        let first = DeskState(label: "First", boards: [outside])
        let focused = BoardState(label: "Focused", width: 520, currentSheetURL: nil)
        let tail = BoardState(label: "Tail", width: 520, currentSheetURL: nil)
        let target = DeskState(label: "Target", boards: [focused, tail], focusedBoardID: focused.id)

        let inserted = BoardState(label: "Inserted", width: 520, currentSheetURL: nil)

        // Act
        let destination = try #require(
            BoardInsertion.insert(
                inserted, in: [first, target], presentedDeskID: first.id, deskID: target.id,
                afterBoardID: missingAnchor ? BoardID() : outside.id))

        // Assert
        #expect(destination.deskIndex == 1)
        #expect(destination.desk.boards.map(\.id) == [focused.id, inserted.id, tail.id])
        #expect(destination.afterBoardID == nil)
    }

    nonisolated enum MissingTarget: CaseIterable, Sendable {
        case desk
        case board
        case presentedDesk
    }

    @Test(arguments: [false, true], [false, true])
    func insertionFocusesRequestedBoardOrFirstBoardInEmptyDesk(_ isEmpty: Bool, _ focus: Bool) throws {
        // Arrange
        let existing = BoardState(label: "Existing", width: 520, currentSheetURL: nil)
        let inserted = BoardState(label: "Inserted", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: isEmpty ? [] : [existing], scrollOffsetX: 180)

        // Act
        let insertion = try #require(
            BoardInsertion.insert(inserted, in: [desk], presentedDeskID: desk.id, focus: focus))

        // Assert
        #expect(insertion.desk.boards.map(\.id) == (isEmpty ? [inserted.id] : [existing.id, inserted.id]))
        #expect(insertion.desk.focusedBoardID == (focus || isEmpty ? inserted.id : existing.id))
        #expect(insertion.desk.scrollOffsetX == (focus || isEmpty ? nil : desk.scrollOffsetX))
    }

    @Test(arguments: MissingTarget.allCases)
    func rejectsMissingTarget(_ target: MissingTarget) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        let presentedDeskID = target == .presentedDesk ? DeskID() : desk.id
        let deskID: DeskID? = target == .desk ? DeskID() : nil
        let afterBoardID: BoardID? = target == .board ? BoardID() : nil

        let inserted = BoardState(label: "Inserted", width: 520, currentSheetURL: nil)

        // Act
        let destination = BoardInsertion.insert(
            inserted, in: [desk], presentedDeskID: presentedDeskID, deskID: deskID, afterBoardID: afterBoardID)

        // Assert
        #expect(destination == nil)
    }
}
