import DenApplication
import DenDomain
import Foundation
import Testing

@MainActor
struct BoardCreationTests {
    @Test(arguments: [false, true])
    func preparationPrecedesMutationAndRecentControlsSaveOrder(recordsRecent: Bool) {
        // Arrange
        let anchor = BoardState(label: "Anchor", width: 520, workingDirectory: "/tmp")
        let board = BoardState(label: "New", width: 640, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [anchor], focusedBoardID: anchor.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let recent = RecentItem.terminal(workingDirectory: "/tmp")
        var events: [String] = []
        let creation = BoardCreation(
            store: shared.store, writer: shared.writer,
            persist: { state in
                #expect(state.desks[0].boards.map(\.id) == [anchor.id, board.id])
                #expect(shared.store.snapshot.recentItems == (recordsRecent ? [recent] : []))
                events.append("save")
                return true
            }, directoryExists: { _ in true })

        // Act
        let result = creation.insert(
            board,
            target: .init(presentedDeskID: desk.id, afterBoardID: anchor.id, focus: false, origin: .cli),
            recentItem: recordsRecent ? recent : nil,
            notify: { notice in
                switch notice {
                case .willInsert(let value):
                    #expect(value == board)
                    #expect(shared.store.snapshot.den.desks[0] == desk)
                    events.append("runtime")
                case .prepareLinkFocus(let id, let origin):
                    #expect(id == anchor.id)
                    #expect(origin == .cli)
                    #expect(shared.store.snapshot.den.desks[0] == desk)
                    events.append("link")
                case .suppressMutationAnimation:
                    #expect(shared.store.snapshot.den.desks[0] == desk)
                    events.append("animation")
                case .didInsert:
                    #expect(shared.store.snapshot.den.desks[0].boards.count == 2)
                    events.append("inserted")
                default: Issue.record("Background creation must not request window focus")
                }
            })

        // Assert
        #expect(result == board.id)
        #expect(shared.store.snapshot.den.desks[0].focusedBoardID == anchor.id)
        #expect(
            events
                == (recordsRecent
                    ? ["runtime", "link", "animation", "inserted", "save"]
                    : ["runtime", "link", "animation", "save", "inserted"]))
    }

    @Test(arguments: [false, true])
    func invalidInsertionDoesNotPrepareMutateOrSave(missingDesk: Bool) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let original = shared.store.snapshot
        let creation = BoardCreation(
            store: shared.store, writer: shared.writer,
            persist: { _ in
                Issue.record("Rejected insertion must not save")
                return true
            },
            directoryExists: { _ in true })

        // Act
        let result = creation.insert(
            BoardState(label: "New", width: 520, workingDirectory: "/tmp"),
            target: .init(
                presentedDeskID: desk.id, deskID: missingDesk ? DeskID() : nil,
                afterBoardID: missingDesk ? nil : BoardID()),
            recentItem: .terminal(workingDirectory: "/tmp"),
            notify: { _ in Issue.record("Rejected insertion must not notify") })

        // Assert
        #expect(result == nil)
        #expect(shared.store.snapshot == original)
    }

    @Test(arguments: [false, true])
    func failedSaveRetainsBoardAndRestoresRecent(recordsRecent: Bool) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        let original: [RecentItem] = [.search("old")]
        let shared = DenStateStore.make(
            initialState: DenSharedState(
                den: DenState(desks: [desk], focusedDeskID: desk.id), recentItems: original))
        var savedStates: [DenState] = []
        let creation = BoardCreation(
            store: shared.store, writer: shared.writer,
            persist: { state in
                savedStates.append(state)
                return false
            }, directoryExists: { _ in true })

        // Act
        let boardID = creation.createTerminal(
            workingDirectory: "/tmp", width: 600, target: .init(presentedDeskID: desk.id),
            recentItem: recordsRecent ? .terminal(workingDirectory: "/tmp") : nil, notify: { _ in })

        // Assert
        #expect(boardID != nil)
        #expect(shared.store.snapshot.den.desks[0].boards.first?.id == boardID)
        #expect(shared.store.snapshot.recentItems == original)
        #expect(savedStates.count == 1)
        #expect(savedStates.first?.desks[0].boards.first?.id == boardID)
    }

    @Test(arguments: [false, true])
    func recentOnlyPersistenceIsUsedOnlyWhenRecordingRecent(recordsRecent: Bool) {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [], focusedBoardID: nil)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        var savedRecent: [[RecentItem]] = []
        let recent = RecentItem.terminal(workingDirectory: "/tmp")
        let creation = BoardCreation(
            store: shared.store, writer: shared.writer,
            persistRecent: {
                savedRecent.append($0)
                return false
            }, directoryExists: { _ in true })

        // Act
        let boardID = creation.createTerminal(
            workingDirectory: "/tmp", width: 520, target: .init(presentedDeskID: desk.id),
            recentItem: recordsRecent ? recent : nil, notify: { _ in })

        // Assert
        #expect(boardID != nil)
        #expect(savedRecent == (recordsRecent ? [[recent]] : []))
        #expect(shared.store.snapshot.recentItems.isEmpty)
    }

    @Test func sharedOperationUsesEachCallsTargetAndNotificationDestination() {
        // Arrange
        let first = DeskState(label: "First", boards: [], focusedBoardID: nil)
        let second = DeskState(label: "Second", boards: [], focusedBoardID: nil)
        let shared = DenStateStore.make(
            initialState: DenSharedState(
                den: DenState(
                    desks: [first, second], focusedDeskID: first.id)))
        let creation = BoardCreation(store: shared.store, writer: shared.writer, directoryExists: { _ in true })
        var firstFocus: [DeskID] = []
        var secondFocus: [DeskID] = []

        // Act
        let firstID = creation.createTerminal(
            workingDirectory: "/tmp/first", width: 500, target: .init(presentedDeskID: first.id),
            notify: { if case .focusInsertedBoard(let id) = $0 { firstFocus.append(id) } })
        let secondID = creation.createTerminal(
            workingDirectory: "/tmp/second", width: 700, target: .init(presentedDeskID: second.id),
            notify: { if case .focusInsertedBoard(let id) = $0 { secondFocus.append(id) } })

        // Assert
        #expect(firstFocus == [first.id])
        #expect(secondFocus == [second.id])
        #expect(shared.store.snapshot.den.desks.map { $0.boards.first?.id } == [firstID, secondID])
        #expect(shared.store.snapshot.den.desks.map { $0.boards.first?.width } == [500, 700])
    }

    @Test func explicitBackgroundDeskPreservesThePresentedDeskAndItsFocus() {
        // Arrange
        let anchor = BoardState(label: "Visible", width: 520, workingDirectory: "/tmp")
        let visible = DeskState(label: "Visible", boards: [anchor], focusedBoardID: anchor.id)
        let hidden = DeskState(label: "Hidden", boards: [], focusedBoardID: nil)
        let shared = DenStateStore.make(
            initialState: DenSharedState(
                den: DenState(
                    desks: [visible, hidden], focusedDeskID: visible.id)))
        let creation = BoardCreation(store: shared.store, writer: shared.writer, directoryExists: { _ in true })

        // Act
        let id = creation.createWeb(
            urlString: "https://example.com", width: 640, searchEngine: .google,
            target: .init(presentedDeskID: visible.id, deskID: hidden.id, focus: false, origin: .cli),
            notify: { if case .focusInsertedBoard = $0 { Issue.record("Must not present the hidden Desk") } })

        // Assert
        #expect(id != nil)
        #expect(shared.store.snapshot.den.desks[0] == visible)
        #expect(shared.store.snapshot.den.focusedDeskID == visible.id)
        #expect(shared.store.snapshot.den.desks[1].boards.first?.id == id)
    }

    @Test func tutorialReuseFocusesExistingBoardWithoutInsertionOrRecent() {
        // Arrange
        let board = BoardState(width: 520, tutorial: TutorialBoardState())
        let desk = DeskState(label: "Desk", boards: [board], focusedBoardID: board.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let original = shared.store.snapshot
        let creation = BoardCreation(store: shared.store, writer: shared.writer, directoryExists: { _ in true })
        var focused: [BoardID] = []

        // Act
        let id = creation.openTutorial(
            width: 700, target: .init(presentedDeskID: desk.id),
            notify: {
                guard case .focusTutorial(let id) = $0 else {
                    Issue.record("Existing Tutorial must not insert a Board")
                    return
                }
                focused.append(id)
            })

        // Assert
        #expect(id == board.id)
        #expect(focused == [board.id])
        #expect(shared.store.snapshot == original)
    }
}
