import DenDomain
import DenPresentationModels
import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct DenControllerQuitBoardTests {
    @Test(arguments: [false, true])
    func quittingNonZmxBoardUsesNormalRemoval(zellij: Bool) {
        // Arrange
        let target =
            zellij
            ? BoardState(label: "Terminal", width: 520, zellijSessionName: "shared")
            : BoardState(label: "Web", width: 520, currentSheetURL: URL(string: "https://example.com/"))
        let neighbor = BoardState(
            label: "Neighbor", width: 520, currentSheetURL: URL(string: "https://example.com/neighbor"))
        withTestWindowModel(desks: [DeskState(label: "Desk", boards: [neighbor, target], focusedBoardID: target.id)]) {
            model, controller in
            // Act
            controller.quitFocusedBoard()

            // Assert
            #expect(controller.focusedDesk?.boards.map(\.id) == [neighbor.id])
            #expect(controller.focusedBoard?.id == neighbor.id)
            #expect(model.pendingConfirmation == nil)
        }
    }

    @Test func cancellingZmxQuitLeavesBoardAndSessionRunning() async {
        // Arrange
        let target = BoardState(label: "Terminal", width: 520, zmxSessionName: "work")
        let runner = QuitCommandRunner(succeeds: true)
        await withTestWindowModel(
            desks: [DeskState(label: "Desk", boards: [target], focusedBoardID: target.id)],
            terminalCommandRunner: runner
        ) { model, controller in
            controller.preferences.setZmxPath("/test/bin/zmx")
            controller.quitFocusedBoard()
            #expect(model.zmxSessionPendingEnd == "work")

            // Act
            model.cancelConfirmation()
            await controller.waitForZmxCommand()

            // Assert
            #expect(model.pendingConfirmation == nil)
            #expect(controller.focusedBoard?.id == target.id)
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
        await withTestWindowModel(
            desks: [DeskState(label: "Desk", boards: [target, child], focusedBoardID: target.id)],
            terminalCommandRunner: runner
        ) { model, controller in
            controller.preferences.setZmxPath("/test/bin/zmx")
            controller.quitFocusedBoard()
            controller.focusBoard(child.id)

            // Act
            model.confirmZmxSessionEnd()
            await controller.waitForZmxCommand()

            // Assert
            let calls = await runner.calls
            #expect(calls == [["kill", "work", "--force"]])
            #expect(model.pendingConfirmation == nil)
            #expect(controller.board(for: target.id) == (succeeds ? nil : target))
            #expect(controller.board(for: child.id) == child)
            #expect(controller.focusedBoard?.id == child.id)
            if !succeeds {
                #expect(controller.latestFeedback?.severity == .error)
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
