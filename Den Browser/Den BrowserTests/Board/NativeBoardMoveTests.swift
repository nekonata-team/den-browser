import DenApplication
import DenDomain
import DenModels
import Testing

@testable import Den_Browser

@MainActor
struct NativeBoardMoveTests {
    @Test(arguments: [false, true], [false, true])
    func movingGroupPreservesDeskFocusAndSavesOrder(sameDesk: Bool, atEnd: Bool) throws {
        // Arrange
        let moved = BoardState(label: "Moved", width: 520, currentSheetURL: nil)
        let side = BoardState(width: 390, targetBoardID: moved.id)
        let first = BoardState(label: "First", width: 520, currentSheetURL: nil)
        let last = BoardState(label: "Last", width: 520, currentSheetURL: nil)
        let source = DeskState(
            label: "Source", boards: atEnd ? [moved, side, first] : [first, moved, side], focusedBoardID: side.id)
        let target = DeskState(label: "Target", boards: [last])
        var saved: DenState?
        let recordSave: (DenState) -> Bool = {
            saved = $0
            return true
        }
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target])),
                    onSave: recordSave),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            let deskID = sameDesk ? source.id : target.id
            let anchorID = atEnd ? nil : (sameDesk ? first.id : last.id)

            // Act
            let result = session.resources.boardMovement.place(side.id, in: deskID, before: anchorID)

            // Assert
            #expect(result)
            #expect(session.navigation.presentedDeskID == source.id)
            let destination = try #require(
                session.resources.state.desks.first(where: { $0.id == deskID }))
            let otherIDs = sameDesk ? [first.id] : [last.id]
            #expect(
                destination.boards.map(\.id)
                    == (atEnd ? otherIDs + [moved.id, side.id] : [moved.id, side.id] + otherIDs))
            #expect(destination.focusedBoardID == (sameDesk ? side.id : last.id))
            #expect(session.resources.state.desks[0].focusedBoardID == (sameDesk ? side.id : first.id))
            #expect(saved?.desks == session.resources.state.desks)
        }
    }

    @Test func transferToEmptyDeskAssignsFocusWithoutSwitchingDesk() {
        // Arrange
        let board = BoardState(label: "Moved", width: 520, currentSheetURL: nil)
        let source = DeskState(label: "Source", boards: [board])
        let target = DeskState(label: "Target", boards: [])
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(makeNativeTestState(desks: [source, target]))),
                configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let session = denWindowSession

            // Act
            let result = session.resources.boardMovement.place(board.id, in: target.id, before: nil)

            // Assert
            #expect(result)
            #expect(session.navigation.presentedDeskID == source.id)
            #expect(session.resources.state.desks[0].focusedBoardID == nil)
            #expect(session.resources.state.desks[1].focusedBoardID == board.id)
        }
    }
}
