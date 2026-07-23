import Foundation
import WebKit

struct AppConfiguration {
    let profileDirectoryURL: URL
    let defaults: UserDefaults
    let initialProfile: PersistedProfile?
    let websiteDataStore: (WebProfileStore) -> WKWebsiteDataStore

    static func current(processInfo: ProcessInfo = .processInfo) -> AppConfiguration {
        guard processInfo.arguments.contains("--ui-testing") else {
            return AppConfiguration(
                profileDirectoryURL: ProfileManager.defaultDirectoryURL(),
                defaults: .standard,
                initialProfile: nil,
                websiteDataStore: { $0.websiteDataStore })
        }

        guard argumentValue(after: "--fixture", in: processInfo.arguments) == "interaction-basics" else {
            preconditionFailure("UI tests require the interaction-basics fixture")
        }

        let runID = processInfo.environment["DEN_UI_TEST_RUN_ID"] ?? UUID().uuidString
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "DenBrowserUITests", directoryHint: .isDirectory)
            .appending(path: runID, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let suiteName = "dev.nekonata.denbrowser.ui-testing"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create UI test preferences")
        }
        defaults.removePersistentDomain(forName: suiteName)

        return AppConfiguration(
            profileDirectoryURL: directoryURL,
            defaults: defaults,
            initialProfile: interactionBasicsProfile(
                singleBoard: processInfo.arguments.contains("--single-board")),
            websiteDataStore: { _ in .nonPersistent() })
    }

    private static func argumentValue(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func interactionBasicsProfile(singleBoard: Bool) -> PersistedProfile {
        let alpha = BoardState(
            id: fixtureID("00000000-0000-0000-0000-000000000301"),
            label: "Alpha",
            width: 320,
            currentSheetURL: URL(string: fixtureSheetURL))
        let bravo = BoardState(
            id: fixtureID("00000000-0000-0000-0000-000000000302"),
            label: "Bravo",
            width: 320,
            currentSheetURL: URL(string: fixtureSheetURL))
        let charlie = BoardState(
            id: fixtureID("00000000-0000-0000-0000-000000000303"),
            label: "Charlie",
            width: 320,
            currentSheetURL: URL(string: fixtureSheetURL))
        let desk = DeskState(
            id: fixtureID("00000000-0000-0000-0000-000000000200"),
            label: "Main",
            boards: singleBoard ? [alpha] : [alpha, bravo, charlie],
            focusedBoardID: alpha.id)
        let secondDesk = DeskState(
            id: fixtureID("00000000-0000-0000-0000-000000000201"),
            label: "Second",
            boards: [])
        let thirdDesk = DeskState(
            id: fixtureID("00000000-0000-0000-0000-000000000202"),
            label: "Third",
            boards: [])
        return PersistedProfile(
            profile: ProfileState(
                id: fixtureID("00000000-0000-0000-0000-000000000100"),
                name: "UI Testing",
                color: .blue,
                webProfileStore: .default),
            den: DenState(desks: [desk, secondDesk, thirdDesk], focusedDeskID: desk.id))
    }

    private static let fixtureSheetURL: String = {
        guard
            let url = Bundle.main.url(forResource: "interaction-basics", withExtension: "html"),
            let html = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("Could not load UI test fixture")
        }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "#"))
        guard let encoded = html.addingPercentEncoding(withAllowedCharacters: allowed) else {
            preconditionFailure("Could not encode UI test fixture")
        }
        return "data:text/html,\(encoded)"
    }()

    private static func fixtureID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid UI test fixture UUID: \(value)")
        }
        return id
    }
}
