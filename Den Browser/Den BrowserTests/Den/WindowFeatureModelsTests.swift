import DenApplication
import DenDomain
import DenModels
import Testing

@testable import Den_Browser

@MainActor
struct WindowFeatureModelsTests {
    @Test func commandsAndFeatureModelsUseTheSameWindowTargetAndConfirmation() {
        let firstBoard = BoardState(label: "First", width: 520, workingDirectory: "/tmp")
        let secondBoard = BoardState(label: "Second", width: 520, workingDirectory: "/tmp")
        let firstDesk = DeskState(label: "First", boards: [firstBoard], focusedBoardID: firstBoard.id)
        let secondDesk = DeskState(label: "Second", boards: [secondBoard], focusedBoardID: secondBoard.id)
        let session = ProfileWindowSession(
            resources: DenProfileResources(
                state: DenStateNormalization.normalize(
                    DenState(desks: [firstDesk, secondDesk], focusedDeskID: firstDesk.id))),
            configuration: makeTestBoardRuntimeConfiguration())
        let composition = DenWindowComposition(session: session)
        let model = composition.model
        composition.connect()
        defer { composition.disconnect() }

        #expect(model.navigation === session.navigation)
        #expect(model.desks.navigation === model.navigation)
        model.desks.focusDesk(secondDesk.id)
        model.boardEditing.renameFocusedBoard(to: "Renamed")
        #expect(model.focusedDesk?.id == secondDesk.id)
        #expect(model.navigation.presentedDeskID == secondDesk.id)
        #expect(model.navigation.previousFocusedDeskID == firstDesk.id)
        #expect(model.boardEditing.focusedBoard?.customLabel == "Renamed")
        #expect(session.resources.state.desks[0].boards[0].customLabel == nil)

        AppActionHandler.perform(.desk(.delete), session: session, windowModel: model)
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
