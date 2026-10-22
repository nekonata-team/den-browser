import DenDomain
import DenPresentationModels
import Testing

@testable import Den_Browser

@MainActor
struct WindowFeatureModelsTests {
    @Test func commandsAndFeatureModelsUseTheSameWindowTargetAndConfirmation() {
        let firstBoard = BoardState(label: "First", width: 520, workingDirectory: "/tmp")
        let secondBoard = BoardState(label: "Second", width: 520, workingDirectory: "/tmp")
        let firstDesk = DeskState(label: "First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let secondDesk = DeskState(label: "Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let controller = DenController(state: DenState(desks: [firstDesk, secondDesk], focusedDeskID: firstDesk.id))
        let composition = DenWindowComposition(controller: controller)
        let model = composition.model
        composition.connect()
        defer { composition.disconnect() }

        model.desks.focusDesk(secondDesk.id)
        model.boardEditing.renameFocusedBoard(to: "Renamed")
        #expect(model.focusedDesk?.id == secondDesk.id)
        #expect(model.boardEditing.focusedBoard?.customLabel == "Renamed")
        #expect(controller.state.desks[0].boards[0].customLabel == nil)

        AppActionHandler.perform(.desk(.delete), controller: controller, windowModel: model)
        guard case .deleteDesk(let pending)? = model.pendingConfirmation else {
            Issue.record("Deletion must request confirmation on the invoking window Model")
            return
        }
        #expect(pending.id == secondDesk.id)
        #expect(model.desks.desks.count == 2)
        model.confirmDeskDeletion()
        #expect(model.desks.desks.map(\.id) == [firstDesk.id])
        #expect(model.focusedDesk?.id == firstDesk.id)
    }
}
