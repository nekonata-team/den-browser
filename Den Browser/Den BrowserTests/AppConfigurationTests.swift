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

    @Test func benchmarkProfileMatchesSelectedScenario() throws {
        // Arrange
        let cases: [(BenchmarkScenario, Int, Int, Int)] = [
            (.emptyDesk, 0, 0, 0),
            (.oneTerminalBoard, 1, 0, 0),
            (.oneWebBoard, 1, 1, 1),
        ]
        #expect(cases.map { $0.0 } == BenchmarkScenario.allCases)
        #expect(
            cases.map { $0.0.rawValue } == [
                "empty-desk",
                "one-terminal-board",
                "one-web-board",
            ])

        for (scenario, boardCount, webBoardCount, loadedSheetCount) in cases {
            let runID = UUID().uuidString
            let suiteName = "dev.nekonata.denbrowser.benchmark.\(runID)"

            // Act
            let configuration = AppConfiguration.benchmark(scenario: scenario, runID: runID)
            defer { configuration.defaults.removePersistentDomain(forName: suiteName) }

            // Assert
            let profile = try #require(configuration.initialProfile)
            let desk = try #require(profile.den.desks.first)
            let webBoards = desk.boards.filter {
                if case .web = $0.content { true } else { false }
            }

            #expect(configuration.isEphemeral)
            #expect(profile.den.focusedDeskID == desk.id)
            #expect(desk.boards.count == boardCount)
            #expect(webBoards.count == webBoardCount)
            #expect(webBoards.filter { $0.currentSheetURL != nil }.count == loadedSheetCount)
            #expect(configuration.websiteDataStore(.default).isPersistent == false)
        }
    }
}
