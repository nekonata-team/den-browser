import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@MainActor
struct OpenBoardModelTests {
    @Test(arguments: [false, true])
    func submitUsesSharedCreationAndSurfacesValidationFailure(directoryExists: Bool) {
        // Arrange
        let anchor = BoardState(label: "Anchor", width: 520, workingDirectory: "/tmp")
        let desk = DeskState(label: "Desk", boards: [anchor], focusedBoardID: anchor.id)
        let shared = DenStateStore.make(
            initialState: DenSharedState(den: DenState(desks: [desk], focusedDeskID: desk.id)))
        let creation = BoardCreation(
            store: shared.reader,
            writer: shared.writer,
            recents: Recents(store: shared.reader, writer: shared.writer),
            directoryExists: { _ in directoryExists })
        var focusedDesks: [DeskID] = []
        let model = OpenBoardModel(
            creation: creation,
            openingRequest: { input, width, afterBoardID in
                BoardCreation.OpenRequest(
                    input: input, width: width ?? 520,
                    target: .init(presentedDeskID: desk.id, afterBoardID: afterBoardID),
                    configuration: .init(
                        searchEngine: .google, zmxConfigured: true, zellijConfigured: true,
                        homeDirectory: URL(fileURLWithPath: "/home/test")))
            },
            notify: { if case .focusInsertedBoard(let id) = $0 { focusedDesks.append(id) } },
            openInDrawer: { _ in
                Issue.record("Board submit must not use Drawer")
                return nil
            })
        model.preparePresentation(afterBoardID: anchor.id)
        model.input = ":terminal project"

        // Act
        model.submit(preferredWidth: 640)

        // Assert
        let boards = shared.store.snapshot.den.desks[0].boards
        #expect(boards.count == (directoryExists ? 2 : 1))
        #expect(boards.first?.id == anchor.id)
        #expect(focusedDesks == (directoryExists ? [desk.id] : []))
        if directoryExists {
            #expect(boards.last?.width == 640)
            #expect(boards.last?.terminalWorkingDirectory == "/home/test/project")
            #expect(shared.store.snapshot.recentItems == [.terminal(workingDirectory: "/home/test/project")])
            #expect(model.message == nil)
        } else {
            #expect(shared.store.snapshot.recentItems.isEmpty)
            #expect(model.message == "Terminal directory does not exist: /home/test/project")
        }
    }
}
