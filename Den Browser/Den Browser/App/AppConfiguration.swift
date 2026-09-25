import Foundation
import WebKit

struct AppConfiguration {
    let profileDirectoryURL: URL
    let defaults: UserDefaults
    let initialProfile: PersistedProfile?
    let isEphemeral: Bool
    let ipcSocketPath: String
    let websiteDataStore: (WebProfileStore) -> WKWebsiteDataStore

    static func current(processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        if processInfo.arguments.contains("--benchmark-scenario") {
            return benchmark(
                runID: processInfo.environment["DEN_BENCHMARK_RUN_ID"] ?? UUID().uuidString,
                arguments: processInfo.arguments)
        }

        guard processInfo.arguments.contains("--ui-testing") else {
            let isPrivateDen = processInfo.arguments.contains("--private-den")
            let isUnitTestHost = processInfo.environment["XCTestConfigurationFilePath"] != nil
            if isUnitTestHost {
                let runID = "\(processInfo.processIdentifier)"
                return unitTest(runID: runID)
            }
            let ipcSocketPath =
                if isPrivateDen {
                    DenSocketPath.temporary(prefix: "den-private")
                } else {
                    DenSocketPath.resolve()
                }
            return AppConfiguration(
                profileDirectoryURL: ProfileManager.defaultDirectoryURL(),
                defaults: .standard,
                initialProfile: isPrivateDen ? privateDenProfile() : nil,
                isEphemeral: isPrivateDen,
                ipcSocketPath: ipcSocketPath,
                websiteDataStore: isPrivateDen ? { _ in .nonPersistent() } : { $0.websiteDataStore })
        }

        let runID = processInfo.environment["DEN_UI_TEST_RUN_ID"] ?? UUID().uuidString
        let runDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserUITests", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
        let directoryURL = runDirectoryURL.appending(path: "Profile", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let initialProfile = initialProfile(from: processInfo.arguments)

        let suiteName = "dev.nekonata.denbrowser.ui-testing.\(runID)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create UI test preferences")
        }
        defaults.removePersistentDomain(forName: suiteName)
        if processInfo.arguments.contains("--enable-sheet-navigation") {
            defaults.set(true, forKey: SheetNavigationManager.enabledKey)
        }

        return AppConfiguration(
            profileDirectoryURL: directoryURL,
            defaults: defaults,
            initialProfile: initialProfile,
            isEphemeral: false,
            ipcSocketPath: DenSocketPath.temporary(prefix: "den-test", identifier: runID),
            websiteDataStore: { _ in .nonPersistent() })
    }

    static func unitTest(runID: String) -> AppConfiguration {
        let suiteName = "dev.nekonata.denbrowser.unit-testing.\(runID)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create unit test preferences")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return AppConfiguration(
            profileDirectoryURL: FileManager.default.temporaryDirectory
                .appending(path: "DenBrowserUnitTests/\(runID)", directoryHint: .isDirectory),
            defaults: defaults,
            initialProfile: nil,
            isEphemeral: true,
            ipcSocketPath: DenSocketPath.temporary(prefix: "den-test", identifier: runID),
            websiteDataStore: { _ in .nonPersistent() })
    }

    private static func benchmark(runID: String, arguments: [String]) -> AppConfiguration {
        let suiteName = "dev.nekonata.denbrowser.benchmark.\(runID)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create benchmark preferences")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let runDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserBenchmark", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
        return AppConfiguration(
            profileDirectoryURL: runDirectoryURL.appending(path: "Profile", directoryHint: .isDirectory),
            defaults: defaults,
            initialProfile: initialProfile(from: arguments),
            isEphemeral: true,
            ipcSocketPath: DenSocketPath.temporary(prefix: "den-benchmark", identifier: runID),
            websiteDataStore: { _ in .nonPersistent() })
    }

    private static func privateDenProfile() -> PersistedProfile {
        PersistedProfile(
            profile: ProfileState(
                id: UUID(),
                name: "Private Den",
                color: .gray,
                webProfileStore: .default),
            den: .sample)
    }

    private static func initialProfile(from arguments: [String]) -> PersistedProfile {
        guard
            let seedPath = argumentValue(after: "--initial-profile", in: arguments),
            let profile = try? loadInitialProfile(at: URL(fileURLWithPath: seedPath))
        else {
            preconditionFailure("A valid initial profile is required")
        }
        return profile
    }

    static func loadInitialProfile(at url: URL) throws -> PersistedProfile {
        try JSONDecoder().decode(PersistedProfile.self, from: Data(contentsOf: url))
    }

    private static func argumentValue(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

}
