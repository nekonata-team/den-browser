import DenDomain
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct AppConfigurationTests {
    @Test func unitTestResourcesAreIsolatedByRun() {
        let firstRunID = UUID().uuidString
        let secondRunID = UUID().uuidString
        let firstSuite = "dev.nekonata.denbrowser.unit-testing.\(firstRunID)"
        let secondSuite = "dev.nekonata.denbrowser.unit-testing.\(secondRunID)"
        let first = AppConfiguration.unitTest(runID: firstRunID)
        let second = AppConfiguration.unitTest(runID: secondRunID)
        defer {
            first.defaults.removePersistentDomain(forName: firstSuite)
            second.defaults.removePersistentDomain(forName: secondSuite)
        }
        first.defaults.set(true, forKey: "isolated")

        #expect(first.isEphemeral)
        #expect(first.profileDirectoryURL != second.profileDirectoryURL)
        #expect(first.ipcSocketPath != second.ipcSocketPath)
        #expect(second.defaults.bool(forKey: "isolated") == false)
        #expect(first.websiteDataStore(.default).isPersistent == false)
    }

    @Test func initialProfileCanBeLoadedFromSeedFile() throws {
        let expected = PersistedProfile(
            profile: ProfileState(
                id: UUID(), name: "Seed", color: .blue, webProfileStore: .default),
            den: .sample)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserInitialProfile-\(UUID().uuidString).json")
        try JSONEncoder().encode(expected).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try AppConfiguration.loadInitialProfile(at: url) == expected)
    }
}
