import DenApplication
import DenDomain
import Testing

@MainActor
struct DeskPresetOperationsTests {
    @Test(arguments: [-1, 0, 1])
    func creationInsertsAfterPresentedDeskAndRestoresPresetFocus(_ focusIndex: Int) throws {
        // Arrange
        let first = DeskState(label: "First", boards: [])
        let presented = DeskState(label: "Presented", boards: [])
        let last = DeskState(label: "Last", boards: [])
        let preset = [
            DeskPresetBoard(label: "Primary", width: 520, initialSheetURL: nil),
            DeskPresetBoard(label: "Side", width: 390, kind: .inspection, targetBoardIndex: 0),
        ]

        // Act
        let creation = try #require(
            DeskCreation.create(
                label: "  Research\n", presetBoards: preset, focusedBoardIndex: focusIndex,
                in: [first, presented, last], presentedDeskID: presented.id))

        // Assert
        let created = creation.createdDesk
        #expect(creation.desks == [first, presented, created, last])
        #expect(created.label == "Research")
        #expect(created.boards.count == 2)
        #expect(created.boards[1].sideBoardTargetBoardID == created.boards[0].id)
        #expect(created.focusedBoardID == created.boards[focusIndex == 1 ? 1 : 0].id)
    }

    nonisolated enum UnavailableCreation: CaseIterable, Sendable {
        case blankLabel
        case deskLimit
        case missingPresentedDesk
        case invalidPreset
    }

    @Test(arguments: UnavailableCreation.allCases)
    func creationRejectsUnavailableInput(_ reason: UnavailableCreation) {
        // Arrange
        let count = reason == .deskLimit ? DeskCreation.maximumDeskCount : 1
        let desks = (0..<count).map { DeskState(label: "Desk \($0)", boards: []) }
        let preset: [DeskPresetBoard] =
            reason == .invalidPreset
            ? [DeskPresetBoard(label: "Orphan", width: 390, kind: .inspection)] : []

        // Act
        let creation = DeskCreation.create(
            label: reason == .blankLabel ? " \n " : "Created", presetBoards: preset, focusedBoardIndex: nil,
            in: desks, presentedDeskID: reason == .missingPresentedDesk ? DeskID() : desks[0].id)

        // Assert
        #expect(creation == nil)
    }

    @Test(arguments: [-1, 1])
    func replacementPreservesDeskIdentityAndReplacesBoardsFocusAndAnchor(_ focusIndex: Int) throws {
        // Arrange
        let old = BoardState(label: "Old", width: 520, currentSheetURL: nil)
        let source = DeskState(label: "Source", boards: [old], scrollOffsetX: 180, anchorBoardID: old.id)
        let other = DeskState(label: "Other", boards: [])
        let preset = [
            DeskPresetBoard(label: "Primary", width: 520, initialSheetURL: nil),
            DeskPresetBoard(label: "Side", width: 390, kind: .inspection, targetBoardIndex: 0),
        ]

        // Act
        let replacement = try #require(
            DeskReplacement.replace(
                source.id, label: "Replaced", presetBoards: preset, focusedBoardIndex: focusIndex,
                in: [other, source]))

        // Assert
        let replaced = replacement.desk
        #expect(replacement.deskIndex == 1)
        #expect(replacement.removedBoards == [old])
        #expect(replaced.id == source.id)
        #expect(replaced.label == "Replaced")
        #expect(replaced.boards.count == 2)
        #expect(replaced.boards.allSatisfy { $0.id != old.id })
        #expect(replaced.boards[1].sideBoardTargetBoardID == replaced.boards[0].id)
        #expect(replaced.focusedBoardID == replaced.boards[focusIndex == 1 ? 1 : 0].id)
        #expect(replaced.anchorBoardID == nil)
        #expect(replaced.scrollOffsetX == nil)
    }

    @Test(arguments: [false, true])
    func replacementRejectsMissingDeskOrInvalidPreset(_ missingDesk: Bool) {
        // Arrange
        let source = DeskState(label: "Source", boards: [])
        let preset: [DeskPresetBoard] =
            missingDesk ? [] : [DeskPresetBoard(label: "Orphan", width: 390, kind: .inspection)]

        // Act
        let replacement = DeskReplacement.replace(
            missingDesk ? DeskID() : source.id, label: "Replaced", presetBoards: preset,
            focusedBoardIndex: nil, in: [source])

        // Assert
        #expect(replacement == nil)
    }
}
