import DenApplication
import DenDomain
import DenModels
import Foundation
import WebKit

@testable import Den_Browser

func makeDrawerTestBoard(
    _ label: String,
    width: Double = 520,
    url: String? = nil
) -> BoardState {
    BoardState(
        label: label,
        width: width,
        currentSheetURL: url.flatMap(URL.init(string:))
    )
}

@MainActor
func withSharedDrawerSessions<T>(
    items: [DrawerItem],
    body: (ProfileWindowSession, ProfileWindowSession) throws -> T
) rethrows -> T {
    let suiteName = "SharedDrawerStoreTests-\(UUID())"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        preconditionFailure("Failed to create isolated test UserDefaults")
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let desks = [makeTestDesk("First"), makeTestDesk("Second")]
    let storage = DenProfileResources(
        state: DenState(
            desks: desks,
            focusedDeskID: desks[0].id,
            drawerItems: items
        )
    )
    let websiteDataStore = WKWebsiteDataStore.nonPersistent()
    let sheetNavigation = SheetNavigationManager(defaults: defaults, scriptSource: "")
    let preferences = AppPreferences(defaults: defaults)
    let makeSession = { (deskID: DeskID) -> ProfileWindowSession in
        ProfileWindowSession(
            resources: storage,
            configuration: makeTestBoardRuntimeConfiguration(
                websiteDataStore: websiteDataStore,
                sheetNavigation: sheetNavigation,
                preferences: preferences
            ),
            presentedDeskID: deskID,
            canPresentDesk: { _ in true },
            onDeskPresentationRequest: { _ in true },
            onWillResetDen: {}
        )
    }
    return try body(makeSession(desks[0].id), makeSession(desks[1].id))
}
