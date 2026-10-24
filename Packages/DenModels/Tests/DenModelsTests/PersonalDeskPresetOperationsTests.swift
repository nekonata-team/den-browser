import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct PersonalDeskPresetOperationsTests {
    @Test(arguments: [false, true], [false, true])
    func savingCommitsBeforePersistenceAndRetainsChangesOnFailure(_ succeeds: Bool, _ isEmpty: Bool) {
        // Arrange
        let board = BoardState(label: "Board", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: isEmpty ? [] : [board])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var saves = 0
        let operations = DeskPresetOperations(
            state: shared.reader, writer: shared.writer,
            persist: { presets in
                #expect(shared.store.snapshot.deskPresets == presets)
                #expect(presets.first?.label == "Routine")
                saves += 1
                return succeeds
            })

        // Act
        let result = operations.save(label: "  Routine  ", desk: desk)

        // Assert
        guard case .created(let persisted) = result else {
            Issue.record("A valid Preset should be created.")
            return
        }
        #expect(persisted == succeeds)
        #expect(saves == 1)
        #expect(shared.store.snapshot.deskPresets.count == 1)
        #expect(shared.store.snapshot.deskPresets.first?.boards.count == (isEmpty ? 0 : 1))
    }

    @Test func emptyPresetRoundTripsAndCreatesAnIndependentEmptyDesk() throws {
        // Arrange
        let desk = DeskState(label: "Research", boards: [])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var savedPresets: [PersonalDeskPreset] = []
        let operations = DeskPresetOperations(
            state: shared.reader, writer: shared.writer,
            persist: {
                savedPresets = $0
                return true
            })

        // Act
        let result = operations.save(label: desk.label, desk: desk)
        let data = try JSONEncoder().encode(savedPresets)
        let restored = try #require(JSONDecoder().decode([PersonalDeskPreset].self, from: data).first)
        let creation = try #require(
            DeskCreation.create(
                label: restored.label, presetBoards: restored.boards, focusedBoardIndex: restored.focusedBoardIndex,
                in: [desk], presentedDeskID: desk.id))

        // Assert
        guard case .created(persisted: true) = result else {
            Issue.record("An empty Desk should be saved as a Preset.")
            return
        }
        #expect(restored == shared.store.snapshot.deskPresets.first)
        #expect(creation.createdDesk.id != desk.id)
        #expect(creation.createdDesk.label == "Research")
        #expect(creation.createdDesk.boards.isEmpty)
        #expect(creation.createdDesk.focusedBoardID == nil)
    }

    @Test(arguments: [false, true])
    func duplicateSaveReturnsReplacementWithoutMutatingOrPersisting(_ isEmpty: Bool) {
        // Arrange
        let board = BoardState(label: "Board", width: 520, currentSheetURL: nil)
        var desk = DeskState(label: "Desk", boards: [board])
        let existing = PersonalDeskPreset(label: "Routine", desk: desk)
        let shared = DenStateStore.make(
            initialState: DenSharedState(
                den: DenState(desks: [desk], focusedDeskID: desk.id), deskPresets: [existing]))
        if isEmpty {
            desk.boards = []
        } else {
            desk.boards[0].width = 900
        }
        var saves = 0
        let operations = DeskPresetOperations(
            state: shared.reader, writer: shared.writer,
            persist: { _ in
                saves += 1
                return true
            })

        // Act
        let result = operations.save(label: " routine ", desk: desk)

        // Assert
        guard case .replacementRequired(let replacement) = result else {
            Issue.record("Saving a duplicate label should require replacement approval.")
            return
        }
        #expect(replacement.id == existing.id)
        #expect(replacement.label == existing.label)
        #expect(replacement.boards.count == (isEmpty ? 0 : 1))
        #expect(replacement.boards.first?.width == (isEmpty ? nil : 900))
        #expect(shared.store.snapshot.deskPresets == [existing])
        #expect(saves == 0)
    }

    @Test func duplicateRenameLeavesSharedPresetsUnchangedWithoutPersistence() {
        // Arrange
        let board = BoardState(label: "Board", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [board])
        let routine = PersonalDeskPreset(label: "Routine", desk: desk)
        let other = PersonalDeskPreset(label: "Other", desk: desk)
        let shared = DenStateStore.make(
            initialState: DenSharedState(
                den: DenState(desks: [desk], focusedDeskID: desk.id), deskPresets: [routine, other]))
        var saves = 0
        let operations = DeskPresetOperations(
            state: shared.reader, writer: shared.writer,
            persist: { _ in
                saves += 1
                return true
            })

        // Act
        let result = operations.rename(routine.id, to: "ＯＴＨＥＲ")

        // Assert
        guard case .duplicateLabel = result else {
            Issue.record("Preset labels should compare without case or width differences.")
            return
        }
        #expect(shared.store.snapshot.deskPresets == [routine, other])
        #expect(saves == 0)
    }
}
