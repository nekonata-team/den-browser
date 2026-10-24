import DenApplication
import DenDomain
import DenModels
import Testing

@MainActor
struct BoardRemovalTests {
    @Test func backgroundGroupRemovalPreparesBeforeMutationAndSavesAfterCleanup() {
        // Arrange
        let primary = BoardState(label: "Primary", width: 520, workingDirectory: "/tmp")
        let side = BoardState(width: 390, targetBoardID: primary.id)
        let focused = BoardState(label: "Focused", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [primary, side, focused], focusedBoardID: focused.id)
        var initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        initial.activeDrag = .board(side.id)
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        let operations = BoardRemoval(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks[0].boards == [focused])
                #expect(shared.store.snapshot.activeDrag == nil)
                events.append("save")
                return true
            })

        // Act
        let removed = operations.remove(
            primary.id, presentedDeskID: desk.id, origin: .cli,
            notify: { notice in
                switch notice {
                case .suppressMutationAnimation:
                    #expect(shared.store.snapshot == initial)
                    events.append("animation")
                case .prepareRemoval(let origin):
                    #expect(origin == .cli)
                    #expect(shared.store.snapshot == initial)
                    events.append("prepare")
                case .removed(let source, let result):
                    #expect(source == desk)
                    #expect(result.removedBoards.map(\.id) == [primary.id, side.id])
                    #expect(shared.store.snapshot.den.desks[0].boards == [focused])
                    #expect(shared.store.snapshot.recentlyRemovedBoards.first == result.historyEntry)
                    events.append("cleanup")
                case .restored:
                    Issue.record("Removal must not restore a Board")
                }
            })

        // Assert
        #expect(removed)
        #expect(events == ["animation", "prepare", "cleanup", "save"])
        #expect(shared.store.snapshot.den.desks[0].focusedBoardID == focused.id)
        #expect(shared.store.snapshot.recentlyRemovedBoards.first?.board.id == primary.id)
        #expect(shared.store.snapshot.recentlyRemovedBoards.first?.sideBoard?.id == side.id)
    }

    @Test func missingBoardDoesNotNotifyMutateOrSave() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let initial = shared.store.snapshot
        let operations = BoardRemoval(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                Issue.record("Missing Board must not save")
                return true
            })

        // Act
        let removed = operations.remove(
            BoardID(), presentedDeskID: initial.den.focusedDeskID,
            notify: { _ in Issue.record("Missing Board must not notify") })

        // Assert
        #expect(!removed)
        #expect(shared.store.snapshot == initial)
    }

    @Test(arguments: [false, true])
    func restorationNotifiesBeforeConsumingHistoryAndRetainsStateOnSaveFailure(present: Bool) {
        // Arrange
        let board = BoardState(label: "Removed", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        let history = RecentlyRemovedBoard(board: board, sourceDeskID: desk.id, sourceBoardIndex: .init(rawValue: 0))
        var initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        initial.recentlyRemovedBoards = [history]
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        let operations = BoardRemoval(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks[0].boards == [board])
                #expect(shared.store.snapshot.recentlyRemovedBoards.isEmpty)
                events.append("save")
                return false
            })

        // Act
        let result = operations.restore(
            presentedDeskID: desk.id, present: present,
            notify: { notice in
                guard case .restored(let restored, let deskID, let shouldPresent) = notice else {
                    Issue.record("Expected restoration notification")
                    return
                }
                #expect(restored == board)
                #expect(deskID == desk.id)
                #expect(shouldPresent == present)
                #expect(shared.store.snapshot.den.desks[0].boards == [board])
                #expect(shared.store.snapshot.recentlyRemovedBoards == [history])
                events.append("present")
            })

        // Assert
        guard case .restored(let id) = result else {
            Issue.record("Expected restoration")
            return
        }
        #expect(id == board.id)
        #expect(shared.store.snapshot.den.desks[0].focusedBoardID == board.id)
        #expect(shared.store.snapshot.recentlyRemovedBoards.isEmpty)
        #expect(events == ["present", "save"])
    }

    @Test func failedRestorationKeepsHistoryAndDoesNotSave() {
        // Arrange
        let board = BoardState(width: 390, targetBoardID: BoardID())
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        var initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        initial.recentlyRemovedBoards = [
            RecentlyRemovedBoard(board: board, sourceDeskID: desk.id, sourceBoardIndex: .init(rawValue: 0))
        ]
        let shared = DenStateStore.make(initialState: initial)
        let operations = BoardRemoval(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                Issue.record("Rejected restoration must not save")
                return true
            })

        // Act
        let result = operations.restore(
            presentedDeskID: desk.id, notify: { _ in Issue.record("Rejected restoration must not notify") })

        // Assert
        guard case .rejected(.targetBoardMissing) = result else {
            Issue.record("Expected missing target")
            return
        }
        #expect(shared.store.snapshot == initial)
    }

    @Test func existingTutorialConsumesHistoryWithoutMutationNotificationOrSave() {
        // Arrange
        let existing = BoardState(width: 520, tutorial: TutorialBoardState())
        let removed = BoardState(width: 520, tutorial: TutorialBoardState())
        let desk = DeskState(label: "Desk", boards: [existing], focusedBoardID: existing.id)
        var initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        initial.recentlyRemovedBoards = [
            RecentlyRemovedBoard(board: removed, sourceDeskID: desk.id, sourceBoardIndex: .init(rawValue: 0))
        ]
        let shared = DenStateStore.make(initialState: initial)
        let operations = BoardRemoval(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                Issue.record("Existing Tutorial must not save")
                return true
            })

        // Act
        let result = operations.restore(
            presentedDeskID: desk.id, notify: { _ in Issue.record("Existing Tutorial must not mutate Boards") })

        // Assert
        guard case .existingTutorial(let id) = result else {
            Issue.record("Expected existing Tutorial")
            return
        }
        #expect(id == existing.id)
        #expect(shared.store.snapshot.den == initial.den)
        #expect(shared.store.snapshot.recentlyRemovedBoards.isEmpty)
    }
}
