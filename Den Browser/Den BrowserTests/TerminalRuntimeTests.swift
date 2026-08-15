import Foundation
import Testing

@testable import Den_Browser

@MainActor
struct TerminalRuntimeTests {
    @Test func terminalCloseNotificationIsDeferredAndCoalesced() async {
        func waitForMainQueue() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }

        var closeCount = 0
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            events: .init(
                onClose: { closeCount += 1 },
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { _, _ in }
            )
        )

        runtime.terminalDidClose(processAlive: false)
        runtime.terminalDidClose(processAlive: false)
        #expect(closeCount == 0)

        await waitForMainQueue()

        #expect(closeCount == 1)
        runtime.dispose()
    }

    @Test func terminalDesktopNotificationForwardsTitleAndBody() {
        var receivedTitle: String?
        var receivedBody: String?
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { title, body in
                    receivedTitle = title
                    receivedBody = body
                }
            )
        )

        runtime.terminalDidRequestDesktopNotification(title: "Build", body: "Finished")

        #expect(receivedTitle == "Build")
        #expect(receivedBody == "Finished")
        runtime.dispose()
    }
}
