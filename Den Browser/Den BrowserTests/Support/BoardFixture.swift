import DenApplication
import DenDomain
import DenModels
import Foundation

@testable import Den_Browser

func makeTestDesk(
    _ label: String,
    boards: [BoardState] = [],
    focusedBoardID: BoardID? = nil
) -> DeskState {
    DeskState(label: label, boards: boards, focusedBoardID: focusedBoardID)
}

func makeTestBoard(
    _ label: String,
    width: Double = 520,
    url: String = "https://example.com/"
) -> BoardState {
    BoardState(label: label, width: width, currentSheetURL: url.isEmpty ? nil : URL(string: url))
}

@MainActor
func makeTestPopupSession(for sourceBoard: BoardState) -> ProfileWindowSession {
    let sourceDesk = makeTestDesk("Desk", boards: [sourceBoard], focusedBoardID: sourceBoard.id)
    return ProfileWindowSession(
        resources: DenProfileResources(
            state: DenStateNormalization.normalize(DenState(desks: [sourceDesk], focusedDeskID: sourceDesk.id))
        ),
        configuration: makeTestBoardRuntimeConfiguration(
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            preferences: AppPreferences(defaults: makeTestDefaults())
        )
    )
}

@MainActor
func waitForTestZmxSessionLoad(_ windowModel: DenWindowModel) async {
    await windowModel.zmxSessions.waitForRefresh()
}
