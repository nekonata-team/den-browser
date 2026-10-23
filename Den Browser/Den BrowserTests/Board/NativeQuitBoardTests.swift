import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct NativeQuitBoardTests {
    @Test(arguments: [false, true])
    func quittingNonZmxBoardUsesNormalRemoval(zellij: Bool) {
        // Arrange
        let target =
            zellij
            ? BoardState(label: "Terminal", width: 520, zellijSessionName: "shared")
            : BoardState(label: "Web", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let neighbor = BoardState(
            label: "Neighbor", width: 520, currentSheetURL: URL(string: "https://example.com/neighbor"))
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [
                            DeskState(label: "Desk", boards: [neighbor, target], focusedBoardID: target.id)
                        ]))), configuration: makeTestBoardRuntimeConfiguration(defaults: denFixtureDefaults))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            // Act
            session.zmx.quitFocusedBoard()

            // Assert
            #expect(session.navigation.focusedDesk?.boards.map(\.id) == [neighbor.id])
            #expect(session.navigation.focusedBoard?.id == neighbor.id)
            #expect(model.pendingConfirmation == nil)
        }
    }

    @Test func cancellingZmxQuitLeavesBoardAndSessionRunning() async {
        // Arrange
        let target = BoardState(label: "Terminal", width: 520, zmxSessionName: "work")
        let runner = QuitCommandRunner(succeeds: true)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [
                            DeskState(label: "Desk", boards: [target], focusedBoardID: target.id)
                        ]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: runner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/test/bin/zmx")
            session.zmx.quitFocusedBoard()
            #expect(model.zmxSessionPendingEnd == "work")

            // Act
            model.cancelConfirmation()
            await session.zmx.waitForZmxCommand()

            // Assert
            #expect(model.pendingConfirmation == nil)
            #expect(session.navigation.focusedBoard?.id == target.id)
            let calls = await runner.calls
            #expect(calls.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func confirmedZmxQuitTargetsOriginalSessionAndKeepsBoardsOnFailure(succeeds: Bool) async {
        // Arrange
        let target = BoardState(label: "Root", width: 520, zmxSessionName: "work")
        let child = BoardState(label: "Child", width: 520, zmxSessionName: "work-child", rootSessionName: "work")
        let runner = QuitCommandRunner(succeeds: succeeds)
        do {
            let denFixtureSuiteName = "NativeWindowFixture-\(UUID().uuidString)"
            let denFixtureDefaults = makeTestDefaults(suiteName: denFixtureSuiteName)
            defer { denFixtureDefaults.removePersistentDomain(forName: denFixtureSuiteName) }
            let denWindowSession = ProfileWindowSession(
                resources: DenProfileResources(
                    state: DenStateNormalization.normalize(
                        makeNativeTestState(desks: [
                            DeskState(label: "Desk", boards: [target, child], focusedBoardID: target.id)
                        ]))),
                configuration: makeTestBoardRuntimeConfiguration(
                    defaults: denFixtureDefaults, terminalCommandRunner: runner))
            let denWindowComposition = DenWindowComposition(session: denWindowSession)
            denWindowComposition.connect()
            defer { denWindowComposition.disconnect() }
            let model = denWindowComposition.model
            let session = denWindowSession

            session.configuration.preferences.setZmxPath("/test/bin/zmx")
            session.zmx.quitFocusedBoard()
            session.boardNavigation.focusBoard(child.id)

            // Act
            model.confirmZmxSessionEnd()
            await session.zmx.waitForZmxCommand()

            // Assert
            let calls = await runner.calls
            #expect(calls == [["kill", "work", "--force"]])
            #expect(model.pendingConfirmation == nil)
            #expect(session.resources.state.board(for: target.id) == (succeeds ? nil : target))
            #expect(session.resources.state.board(for: child.id) == child)
            #expect(session.navigation.focusedBoard?.id == child.id)
            if !succeeds {
                #expect(session.feedback.latest?.severity == .error)
            }
        }
    }
}

private actor QuitCommandRunner: TerminalCommandRunning {
    let succeeds: Bool
    private(set) var calls: [[String]] = []

    init(succeeds: Bool) { self.succeeds = succeeds }

    func run(executablePath: String, arguments: [String], timeout: Duration) async throws -> TerminalCommandResult {
        calls.append(arguments)
        return TerminalCommandResult(terminationStatus: succeeds ? 0 : 1, standardOutput: "")
    }
}
