import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct ZmxSessionsModelTests {
    @Test func loadsFiltersAndSelectsSessionsWithoutDenStore() async {
        let model = ZmxSessionsModel(
            client: ZmxClient(
                executablePath: "/opt/homebrew/bin/zmx",
                commandRunner: ModelTerminalCommandRunner(
                    responses: [
                        ["list"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: "name=den\n"
                                + "name=den-vi\tden.root=den\n"
                                + "name=old-root-debug\tden.root=old-root\n")
                    ])))

        model.refresh()
        await model.waitForRefresh()

        #expect(model.groups.count == 2)
        #expect(model.sessionNames == ["den", "den-vi", "old-root-debug"])
        model.setQuery("vi")
        #expect(
            model.filteredGroups
                == [
                    ZmxSessionGroup(
                        rootSessionName: "den",
                        isRootActive: true,
                        childSessionNames: ["den-vi"])
                ])
        #expect(model.selectedSessionName == "den")
        model.clearFilter()
        model.select(by: 1)
        #expect(model.selectedSessionName == "den-vi")

        model.toggleMarking("den-vi")
        model.select(sessionName: "den")
        model.toggleMarking("den")
        #expect(model.markedSessionNames == ["den", "den-vi"])
        model.refresh()
        await model.waitForRefresh()
        #expect(model.selectedSessionName == "den")
        #expect(model.markedSessionNames == ["den", "den-vi"])
        model.requestDeletion()
        #expect(model.pendingDeletion == ["den", "den-vi"])
    }

    @Test func failedRefreshClearsSessionsAndReportsMessage() async {
        let model = ZmxSessionsModel(
            client: ZmxClient(
                executablePath: "/opt/homebrew/bin/zmx",
                commandRunner: ModelTerminalCommandRunner(
                    responses: [
                        ["list"]: TerminalCommandResult(
                            terminationStatus: 1,
                            standardOutput: "")
                    ])))

        model.refresh()
        await model.waitForRefresh()

        #expect(model.groups.isEmpty)
        #expect(model.selectedSessionName == nil)
        #expect(model.message == "Could not list zmx Sessions.")
        #expect(!model.isLoading)
    }

    @Test func endingMarkedSessionsAttemptsEveryTarget() async {
        let model = ZmxSessionsModel(
            client: ZmxClient(
                executablePath: "/opt/homebrew/bin/zmx",
                commandRunner: ModelTerminalCommandRunner(
                    responses: [
                        ["list"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: "name=den\nname=den-vi\tden.root=den\n"),
                        ["kill", "den", "--force"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: ""),
                    ])))

        model.refresh()
        await model.waitForRefresh()
        model.markAllVisible()
        model.requestDeletion()
        model.kill(model.pendingDeletion)
        await model.waitForRefresh()

        #expect(model.message == "Could not end den-vi.")
    }

    @Test func endingFocusedSessionMovesToTheNearestSurvivingSession() async {
        let model = ZmxSessionsModel(
            client: ZmxClient(
                executablePath: "/opt/homebrew/bin/zmx",
                commandRunner: ModelTerminalCommandRunner(
                    responses: [
                        ["list"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: "name=den\n"
                                + "name=den-vi\tden.root=den\n"
                                + "name=den-nvim\tden.root=den\n")
                    ])))

        model.refresh()
        await model.waitForRefresh()
        model.select(sessionName: "den-vi")
        model.requestDeletion()
        model.kill(
            model.pendingDeletion,
            using: ZmxClient(
                executablePath: "/opt/homebrew/bin/zmx",
                commandRunner: ModelTerminalCommandRunner(
                    responses: [
                        ["list"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: "name=den\nname=den-nvim\tden.root=den\n"),
                        ["kill", "den-vi", "--force"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: ""),
                    ])))
        await model.waitForRefresh()
        #expect(model.selectedSessionName == "den-nvim")

        model.select(sessionName: "den-nvim")
        model.requestDeletion()
        model.kill(
            model.pendingDeletion,
            using: ZmxClient(
                executablePath: "/opt/homebrew/bin/zmx",
                commandRunner: ModelTerminalCommandRunner(
                    responses: [
                        ["list"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: "name=den\n"),
                        ["kill", "den-nvim", "--force"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: ""),
                    ])))
        await model.waitForRefresh()
        #expect(model.selectedSessionName == "den")
    }
}

private struct ModelTerminalCommandRunner: TerminalCommandRunning, Sendable {
    let responses: [[String]: TerminalCommandResult]

    func run(executablePath: String, arguments: [String]) -> TerminalCommandResult? {
        responses[arguments]
    }
}
