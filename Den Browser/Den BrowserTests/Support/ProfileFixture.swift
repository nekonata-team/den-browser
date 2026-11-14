import DenApplication
import DenDomain
import DenInfrastructure
import DenModels
import Foundation

@testable import Den_Browser

func makeTemporaryProfileDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "den-browser-profile-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

func makeProfileURL(_ id: ProfileID, in directory: URL) -> URL {
    directory.appending(path: "\(id.rawValue.uuidString.lowercased()).json")
}

@MainActor
func makeTestProfileManager(
    directory: URL,
    quarantineFile: ((URL, URL) throws -> Void)? = nil,
    isEphemeral: Bool = false,
    webExtensionDescriptors: [WebExtensionDescriptor] = [],
    uBOLiteEnabled: Bool = false
) -> ProfileManager {
    let suiteName = "ProfileManagerPreferences-\(UUID().uuidString)"
    let defaults = makeTestDefaults(suiteName: suiteName)
    let preferences = AppPreferences(defaults: defaults)
    if uBOLiteEnabled { preferences.setUBOLiteEnabled(true) }
    let navigation = SheetNavigationManager(
        defaults: defaults,
        scriptSource: ""
    )
    return ProfileManager(
        directoryURL: directory,
        sheetNavigation: navigation,
        preferences: preferences,
        removeDataStore: { _ in },
        removeExtensionData: { profileID in
            try ProfileExtensionDataStore.remove(
                profileID,
                directoryURL: directory.appending(path: "WebExtensions")
            )
        },
        isEphemeral: isEphemeral,
        websiteDataStore: { _ in .nonPersistent() },
        webExtensionDescriptors: webExtensionDescriptors,
        quarantineFile: quarantineFile ?? { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    )
}

@MainActor
func makeExtensionFixtureDescriptor() -> WebExtensionDescriptor {
    WebExtensionDescriptor(
        identifier: "test.extension",
        directoryURL: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/MV3Extension", directoryHint: .isDirectory)
    )
}
