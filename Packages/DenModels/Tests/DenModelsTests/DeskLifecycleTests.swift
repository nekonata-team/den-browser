import DenApplication
import DenDomain
import DenModels
import Testing

@MainActor
struct DeskLifecycleTests {
    @Test(arguments: [false, true])
    func creationPresentsOnlyWhenRequestedAndSavesBeforeTutorialEvent(focus: Bool) throws {
        // Arrange
        let first = DeskState(label: "First", boards: [])
        let second = DeskState(label: "Second", boards: [])
        let shared = DenStateStore.make(
            initialState: DenSharedState(
                den: DenState(
                    desks: [first, second], focusedDeskID: first.id)))
        var events: [String] = []
        let lifecycle = DeskLifecycle(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks.map(\.label) == ["First", "New", "Second"])
                events.append("save")
                return true
            })

        // Act
        let created = try #require(
            lifecycle.create(
                label: "  New  ", boards: [], focusedBoardIndex: nil, presentedDeskID: first.id, focus: focus,
                notify: { notice in
                    switch notice {
                    case .presentCreatedDesk(let id):
                        #expect(shared.store.snapshot.den.desks[1].id == id)
                        DeskUpdates(store: shared.reader, writer: shared.writer).recordPresentedDesk(id)
                        events.append("present")
                    case .didCreateDesk: events.append("tutorial")
                    default: Issue.record("Unexpected creation notification")
                    }
                }))

        // Assert
        #expect(shared.store.snapshot.den.desks.map(\.id) == [first.id, created.id, second.id])
        #expect(shared.store.snapshot.den.focusedDeskID == (focus ? created.id : first.id))
        #expect(events == (focus ? ["present", "save", "tutorial"] : ["save", "tutorial"]))
    }

    @Test(arguments: [false, true])
    func deletionUsesCallingWindowsAvailabilityAndCleansBeforeSaving(available: Bool) {
        // Arrange
        let board = BoardState(label: "Removed", width: 520, currentSheetURL: nil)
        let removed = DeskState(label: "Removed", boards: [board], focusedBoardID: board.id)
        let replacement = DeskState(label: "Replacement", boards: [])
        var initial = DenSharedState(den: DenState(desks: [removed, replacement], focusedDeskID: removed.id))
        initial.activeDrag = .desk(removed.id)
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        let lifecycle = DeskLifecycle(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks == [replacement])
                #expect(state.focusedDeskID == replacement.id)
                #expect(shared.store.snapshot.activeDrag == nil)
                events.append("save")
                return true
            })

        // Act
        let deleted = lifecycle.delete(
            removed.id, presentedDeskID: removed.id, isAvailable: { available && $0 == replacement.id },
            notify: { notice in
                switch notice {
                case .willDelete(let desk, let replacementID, let wasPresented):
                    #expect(shared.store.snapshot.den.desks == [removed, replacement])
                    #expect(desk == removed)
                    #expect(wasPresented)
                    DeskUpdates(store: shared.reader, writer: shared.writer).recordPresentedDesk(replacementID)
                    events.append("prepare")
                case .didDelete(let desk, let wasPresented):
                    #expect(shared.store.snapshot.den.desks == [replacement])
                    #expect(desk.id == removed.id)
                    #expect(wasPresented)
                    events.append("invalidate")
                default: Issue.record("Unexpected deletion notification")
                }
            })

        // Assert
        #expect(deleted == available)
        #expect(events == (available ? ["prepare", "invalidate", "save"] : []))
        if !available { #expect(shared.store.snapshot == initial) }
    }

    @Test func replacementDisposesBeforeMutationAndKeepsNewStateAfterFailedSave() {
        // Arrange
        let board = BoardState(label: "Old", width: 520, currentSheetURL: nil)
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id, anchorBoardID: board.id)
        var initial = DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id))
        initial.activeDrag = .board(board.id)
        let shared = DenStateStore.make(initialState: initial)
        var events: [String] = []
        let lifecycle = DeskLifecycle(
            store: shared.reader, writer: shared.writer,
            persist: { state in
                #expect(state.desks[0].label == "Replaced")
                #expect(shared.store.snapshot.activeDrag == nil)
                events.append("save")
                return false
            })

        // Act
        let replaced = lifecycle.replace(
            desk.id, label: "Replaced", boards: [.init(label: "New", width: 640, initialSheetURL: nil)],
            focusedBoardIndex: .init(rawValue: 0),
            notify: { notice in
                switch notice {
                case .willReplace(let removed):
                    #expect(removed == [board])
                    #expect(shared.store.snapshot.den.desks[0] == desk)
                    events.append("dispose")
                case .didReplace(let id, let removed):
                    #expect(id == desk.id)
                    #expect(removed == [board])
                    #expect(shared.store.snapshot.den.desks[0].boards[0].label == "New")
                    events.append("invalidate")
                default: Issue.record("Unexpected replacement notification")
                }
            })

        // Assert
        #expect(replaced)
        #expect(events == ["dispose", "invalidate", "save"])
        #expect(shared.store.snapshot.den.desks[0].id == desk.id)
        #expect(shared.store.snapshot.den.desks[0].anchorBoardID == nil)
        #expect(shared.store.snapshot.den.desks[0].boards[0].id != board.id)
    }

    @Test func removedConfirmationTargetDoesNotDisposeOrSave() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let initial = shared.store.snapshot
        let lifecycle = DeskLifecycle(
            store: shared.reader, writer: shared.writer,
            persist: { _ in
                Issue.record("Missing target must not save")
                return true
            })

        // Act
        let replaced = lifecycle.replace(
            DeskID(), label: "Replacement", boards: [.init(label: "New", width: 520, initialSheetURL: nil)],
            focusedBoardIndex: nil, notify: { _ in Issue.record("Missing target must not notify") })

        // Assert
        #expect(!replaced)
        #expect(shared.store.snapshot == initial)
    }

    @Test func duplicationReturnsSourceAndCopiesWithNewIdentityWithoutTutorial() throws {
        // Arrange
        let board = BoardState(label: "Board", width: 640, currentSheetURL: nil)
        let tutorial = BoardState(width: 520, tutorial: TutorialBoardState())
        let source = DeskState(label: "Source", boards: [board, tutorial], focusedBoardID: board.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [source], focusedDeskID: source.id)))
        let lifecycle = DeskLifecycle(store: shared.reader, writer: shared.writer)

        // Act
        let result = try #require(lifecycle.duplicate(source.id, presentedDeskID: source.id, notify: { _ in }))

        // Assert
        #expect(result.source == source)
        #expect(result.copy.id != source.id)
        #expect(result.copy.boards.count == 1)
        #expect(result.copy.boards[0].id != board.id)
        #expect(result.copy.boards[0].width == board.width)
    }
}
