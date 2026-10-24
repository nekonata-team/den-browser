import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct InputOpeningTests {
    @Test(arguments: [false, true])
    func essentialAndClipboardUseSharedCreationOrDrawer(inDrawer: Bool) throws {
        // Arrange
        let desk = DeskState(label: "Desk", boards: [])
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let recents = Recents(store: shared.reader, writer: shared.writer)
        let creation = BoardCreation(
            store: shared.reader, writer: shared.writer, recents: recents, directoryExists: { _ in true })
        let drawer = DrawerItems(store: shared.reader, writer: shared.writer)
        let opening = InputOpening(creation: creation, drawer: drawer)
        let context = InputOpening.Context(
            width: 640, target: .init(presentedDeskID: desk.id),
            configuration: .init(
                searchEngine: .google, zmxConfigured: false, zellijConfigured: false,
                homeDirectory: URL(fileURLWithPath: "/tmp")))
        let essential = Essential(name: "Docs", key: "d", input: "https://example.com/")
        var stages: [String] = []
        let notify: (InputOpening.Notice) -> Void = { notice in
            switch notice {
            case .willOpenBoard: stages.append("panel")
            case .keptInDrawer: stages.append("kept")
            default: break
            }
        }
        // Act
        let result = opening.launch(essential, context: context, inDrawer: inDrawer, notify: notify)
        let empty = opening.openClipboard("   ", context: context, inDrawer: inDrawer, notify: notify)
        // Assert
        guard case .accepted = result, case .rejected("Clipboard is empty.") = empty else {
            Issue.record("Unexpected input result")
            return
        }
        #expect(stages == (inDrawer ? ["kept"] : ["panel"]))
        #expect(shared.store.snapshot.den.desks[0].boards.count == (inDrawer ? 0 : 1))
        #expect(shared.store.snapshot.den.drawerItems.count == (inDrawer ? 1 : 0))
        #expect(shared.store.snapshot.recentItems.count == (inDrawer ? 0 : 1))
        #expect(shared.store.snapshot.den.desks[0].boards.first?.width == (inDrawer ? nil : 640))
    }

    @Test func drawerRejectsCommandsBeforeStateOrPresentationChanges() {
        // Arrange
        let shared = DenStateStore.make(initialState: DenSharedState(den: .sample))
        let initial = shared.store.snapshot
        let creation = BoardCreation(
            store: shared.reader, writer: shared.writer,
            recents: Recents(store: shared.reader, writer: shared.writer), directoryExists: { _ in true })
        let opening = InputOpening(creation: creation, drawer: DrawerItems(store: shared.reader, writer: shared.writer))
        let context = InputOpening.Context(
            width: 520, target: .init(presentedDeskID: initial.den.focusedDeskID),
            configuration: .init(
                searchEngine: .google, zmxConfigured: true, zellijConfigured: true,
                homeDirectory: URL(fileURLWithPath: "/tmp")))
        // Act
        let result = opening.open(
            ":terminal", context: context, inDrawer: true,
            notify: { _ in Issue.record("Rejected command must not notify") })
        // Assert
        guard case .rejected = result else {
            Issue.record("Drawer cannot open commands")
            return
        }
        #expect(shared.store.snapshot == initial)
    }
}
