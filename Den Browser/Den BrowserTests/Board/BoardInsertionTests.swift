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

        // Act
        let destination = try #require(
            BoardInsertion.resolve(in: [desk], presentedDeskID: desk.id, afterBoardID: anchorID))

        // Assert
        #expect(destination.deskIndex == 0)
        #expect(destination.boardIndex == 2)
        #expect(destination.afterBoardID == anchorID)
    }

    @Test func defaultsToPresentedDeskFocusWithoutCreatingExplicitAnchor() throws {
        // Arrange
        let other = DeskState(label: "Other", boards: [])
        let focused = BoardState(label: "Focused", width: 520, currentSheetURL: nil)
        let tail = BoardState(label: "Tail", width: 520, currentSheetURL: nil)
        let presented = DeskState(label: "Presented", boards: [focused, tail], focusedBoardID: focused.id)

        // Act
        let destination = try #require(
            BoardInsertion.resolve(in: [other, presented], presentedDeskID: presented.id))

        // Assert
        #expect(destination.deskIndex == 1)
        #expect(destination.boardIndex == 1)
        #expect(destination.afterBoardID == nil)
    }

    @Test func explicitAnchorSelectsItsOwningDesk() throws {
        // Arrange
        let presented = DeskState(label: "Presented", boards: [])
        let anchor = BoardState(label: "Anchor", width: 520, currentSheetURL: nil)
        let owning = DeskState(label: "Owning", boards: [anchor], focusedBoardID: anchor.id)

        // Act
        let destination = try #require(
            BoardInsertion.resolve(in: [presented, owning], presentedDeskID: presented.id, afterBoardID: anchor.id))

        // Assert
        #expect(destination.deskIndex == 1)
        #expect(destination.boardIndex == 1)
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

        // Act
        let destination = try #require(
            BoardInsertion.resolve(
                in: [first, target], presentedDeskID: first.id, deskID: target.id,
                afterBoardID: missingAnchor ? BoardID() : outside.id))

        // Assert
        #expect(destination.deskIndex == 1)
        #expect(destination.boardIndex == 1)
        #expect(destination.afterBoardID == nil)
    }

    nonisolated enum MissingTarget: CaseIterable, Sendable {
        case desk
        case board
        case presentedDesk
    }

    @Test(arguments: MissingTarget.allCases)
    func rejectsMissingTarget(_ target: MissingTarget) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        let presentedDeskID = target == .presentedDesk ? DeskID() : desk.id
        let deskID: DeskID? = target == .desk ? DeskID() : nil
        let afterBoardID: BoardID? = target == .board ? BoardID() : nil

        // Act
        let destination = BoardInsertion.resolve(
            in: [desk], presentedDeskID: presentedDeskID, deskID: deskID, afterBoardID: afterBoardID)

        // Assert
        #expect(destination == nil)
    }
}
