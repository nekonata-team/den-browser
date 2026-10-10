import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct ZmxSessionsModelTests {
    @Test func loadsFiltersAndSelectsSessions() async {
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

    @Test func selectionWrapsAtBothEnds() async {
        let model = ZmxSessionsModel(
            client: ZmxClient(
                executablePath: "/opt/homebrew/bin/zmx",
                commandRunner: ModelTerminalCommandRunner(
                    responses: [
                        ["list"]: TerminalCommandResult(
                            terminationStatus: 0,
                            standardOutput: "name=den\nname=den-vi\n")
                    ])))

        model.refresh()
        await model.waitForRefresh()
        model.select(sessionName: "den")
        model.select(by: -1)
        #expect(model.selectedSessionName == "den-vi")
        model.select(by: 1)
        #expect(model.selectedSessionName == "den")
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
        #expect(model.message == "Could not list zmx Sessions: Command exited with status 1")
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

        #expect(model.message?.contains("Could not end den-vi") == true)
        #expect(model.message?.contains("Missing stub response") == true)
    }

    @Test func endingFocusedSessionMovesToTheNearestSurvivingSession() async {
        var client = ZmxClient(
            executablePath: "/opt/homebrew/bin/zmx",
            commandRunner: ModelTerminalCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\n"
                            + "name=den-vi\tden.root=den\n"
                            + "name=den-nvim\tden.root=den\n")
                ]))
        let model = ZmxSessionsModel(operations: { zmxOperations(client) })

        model.refresh()
        await model.waitForRefresh()
        model.select(sessionName: "den-vi")
        model.requestDeletion()
        client = ZmxClient(
            executablePath: "/opt/homebrew/bin/zmx",
            commandRunner: ModelTerminalCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\nname=den-nvim\tden.root=den\n"),
                    ["kill", "den-vi", "--force"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: ""),
                ]))
        model.kill(model.pendingDeletion)
        await model.waitForRefresh()
        #expect(model.selectedSessionName == "den-nvim")

        model.select(sessionName: "den-nvim")
        model.requestDeletion()
        client = ZmxClient(
            executablePath: "/opt/homebrew/bin/zmx",
            commandRunner: ModelTerminalCommandRunner(
                responses: [
                    ["list"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: "name=den\n"),
                    ["kill", "den-nvim", "--force"]: TerminalCommandResult(
                        terminationStatus: 0,
                        standardOutput: ""),
                ]))
        model.kill(model.pendingDeletion)
        await model.waitForRefresh()
        #expect(model.selectedSessionName == "den")
    }

    @Test(arguments: [false, true], [false, true])
    func cancelledRefreshDoesNotChangeStoppedOrRestartedModel(restart: Bool, fails: Bool) async {
        // Arrange
        let deferred = DeferredZmxOperation<ZmxSessionSnapshot>()
        let current = ZmxSessionSnapshot(
            groups: [ZmxSessionGroup(rootSessionName: "current", isRootActive: true, childSessionNames: [])],
            processNames: ["current": "shell"])
        var operations = ZmxSessionsModel.Operations(load: { try await deferred.run() }, kill: { _ in })
        let model = ZmxSessionsModel(operations: { operations })
        model.start(selectedSessionName: nil)
        await deferred.waitUntilStarted()
        let completion = await pendingCompletion(of: model)

        // Act
        model.stop()
        if restart {
            operations = ZmxSessionsModel.Operations(load: { current }, kill: { _ in })
            model.start(selectedSessionName: "current")
            await model.waitForRefresh()
        }
        deferred.complete(
            fails
                ? .failure(TerminalCommandError(message: "Old refresh failed"))
                : .success(
                    ZmxSessionSnapshot(
                        groups: [ZmxSessionGroup(rootSessionName: "old", isRootActive: true, childSessionNames: [])],
                        processNames: ["old": "editor"])))
        await completion.value

        // Assert
        #expect(model.groups == (restart ? current.groups : []))
        #expect(model.processNames == (restart ? current.processNames : [:]))
        #expect(model.selectedSessionName == (restart ? "current" : nil))
        #expect(!model.isLoading)
        #expect(model.message == nil)
    }

    @Test(arguments: [false, true], [false, true])
    func cancelledKillDoesNotChangeStoppedOrRestartedModel(restart: Bool, fails: Bool) async {
        // Arrange
        let deferred = DeferredZmxOperation<Void>()
        let old = ZmxSessionSnapshot(
            groups: [ZmxSessionGroup(rootSessionName: "old", isRootActive: true, childSessionNames: [])],
            processNames: [:])
        let current = ZmxSessionSnapshot(
            groups: [ZmxSessionGroup(rootSessionName: "current", isRootActive: true, childSessionNames: [])],
            processNames: ["current": "shell"])
        var operations = ZmxSessionsModel.Operations(load: { old }, kill: { _ in try await deferred.run() })
        let model = ZmxSessionsModel(operations: { operations })
        model.start(selectedSessionName: "old")
        await model.waitForRefresh()
        model.kill("old")
        await deferred.waitUntilStarted()
        let completion = await pendingCompletion(of: model)

        // Act
        model.stop()
        if restart {
            operations = ZmxSessionsModel.Operations(load: { current }, kill: { _ in })
            model.start(selectedSessionName: "current")
            await model.waitForRefresh()
        }
        deferred.complete(
            fails ? .failure(TerminalCommandError(message: "Old kill failed")) : .success(()))
        await completion.value
        await model.waitForRefresh()

        // Assert
        #expect(model.groups == (restart ? current.groups : []))
        #expect(model.processNames == (restart ? current.processNames : [:]))
        #expect(model.selectedSessionName == (restart ? "current" : nil))
        #expect(!model.isLoading)
        #expect(model.message == nil)
    }
}

private func zmxOperations(_ client: ZmxClient) -> ZmxSessionsModel.Operations {
    ZmxSessionsModel.Operations(
        load: { try await client.sessionSnapshot() },
        kill: { try await client.killSession($0) })
}

private extension ZmxSessionsModel {
    convenience init(client: ZmxClient) {
        self.init(operations: { zmxOperations(client) })
    }
}

private struct ModelTerminalCommandRunner: TerminalCommandRunning, Sendable {
    let responses: [[String]: TerminalCommandResult]

    func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> TerminalCommandResult {
        guard let response = responses[arguments] else {
            throw TerminalCommandError(message: "Missing stub response for \(arguments)")
        }
        return response
    }
}

@MainActor
private final class DeferredZmxOperation<Value: Sendable> {
    private let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<Value, any Error>?

    func run() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.continuation.yield(())
        }
    }

    func waitUntilStarted() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }

    func complete(_ result: Result<Value, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor
private func pendingCompletion(of model: ZmxSessionsModel) async -> Task<Void, Never> {
    let started = AsyncStream<Void>.makeStream()
    let completion = Task {
        started.continuation.yield(())
        await model.waitForRefresh()
    }
    var iterator = started.stream.makeAsyncIterator()
    _ = await iterator.next()
    return completion
}
