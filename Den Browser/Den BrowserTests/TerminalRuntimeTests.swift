import Foundation
import GhosttyTerminal
import Testing

@testable import Den_Browser

@MainActor
struct TerminalRuntimeTests {
    @Test func terminalViewReportsAnEmptySelectionWithoutMarkedText() {
        let view = DenTerminalView(frame: .zero)

        #expect(view.selectedRange() == NSRange(location: 0, length: 0))
    }

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

    @Test func terminalOpenURLForwardsURL() {
        var receivedURL: String?
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { receivedURL = $0 },
                onNotification: { _, _ in }
            )
        )

        runtime.terminalDidRequestOpenURL("https://example.com/path", kind: .text)

        #expect(receivedURL == "https://example.com/path")
        runtime.dispose()
    }

    @Test func terminalOpenURLNotifiesURL() {
        var callbacks: [String] = []
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in callbacks.append("url") },
                onNotification: { _, _ in }
            )
        )

        runtime.terminalDidRequestOpenURL("https://example.com/path", kind: .text)

        #expect(callbacks == ["url"])
        runtime.dispose()
    }

    @Test func terminalActivityCallbacksUpdateLiveState() {
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { _, _ in }
            )
        )

        runtime.terminalDidReportProgress(state: .set, percent: 64)
        runtime.terminalDidFinishCommand(exitCode: 1, durationNanos: 2_500_000_000)
        runtime.terminalDidRingBell()

        #expect(runtime.progressPercent == 64)
        #expect(runtime.lastCommandResult == .init(exitCode: 1, durationNanos: 2_500_000_000))
        #expect(runtime.lastBellDate != nil)

        runtime.terminalDidReportProgress(state: .remove, percent: nil)
        #expect(runtime.progressState == nil)
        #expect(runtime.progressPercent == nil)
        runtime.dispose()
    }

    @Test func terminalRuntimeConfiguresEnvironmentVariables() {
        let boardID = UUID()
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            boardID: boardID,
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { _, _ in }
            )
        )

        let envVars = runtime.terminalView.configuration.envVars
        #expect(envVars["DEN_BOARD_ID"] == boardID.uuidString)
        #expect(envVars["DEN_SOCKET"]?.contains(".den/den.sock") == true)
        runtime.dispose()
    }

    @Test func terminalRuntimeReadViewportTextAndSendText() {
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { _, _ in }
            )
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = runtime.terminalView

        runtime.sendText("echo hello\n")
        let text = runtime.readViewportText()
        #expect(text != nil)
        runtime.dispose()
    }

    @Test func terminalRuntimeRunCommandExecutesShellCommand() async {
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            command: "/bin/zsh -f",
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { _, _ in }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = runtime.terminalView
        window.makeKeyAndOrderFront(nil)
        defer {
            runtime.dispose()
            window.orderOut(nil)
        }

        let marker = "den_terminal_run_marker"
        runtime.runCommand("printf \(marker)")

        for _ in 0..<40 {
            if runtime.readViewportText()?.contains(marker) == true {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(runtime.readViewportText()?.contains(marker) == true)
    }

    @Test func terminalRuntimeQueuesCommandUntilSurfaceIsReady() async {
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            command: "/bin/zsh -f",
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { _, _ in }
            )
        )
        let marker = "den_terminal_ready_marker"

        runtime.runCommand("printf \(marker)")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = runtime.terminalView
        window.makeKeyAndOrderFront(nil)
        defer {
            runtime.dispose()
            window.orderOut(nil)
        }

        for _ in 0..<40 {
            if runtime.readViewportText()?.contains(marker) == true {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        #expect(runtime.readViewportText()?.contains(marker) == true)
    }

    @Test func terminalRuntimeSendSignalFailsWhenNoProcessRunning() {
        let runtime = TerminalRuntime(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            events: .init(
                onClose: {},
                onFocus: {},
                onWorkingDirectoryChange: { _ in },
                onTitleChange: { _ in },
                onOpenURL: { _ in },
                onNotification: { _, _ in }
            )
        )

        #expect(throws: TerminalRuntime.SignalError.self) {
            try runtime.sendSignal(SIGTERM)
        }
        runtime.dispose()
    }

    @Test func denIPCServiceParseSignalSupportsNamesAndNumbers() {
        #expect(DenIPCService.parseSignal("TERM") == .init(number: SIGTERM, name: "SIGTERM"))
        #expect(DenIPCService.parseSignal("sigterm") == .init(number: SIGTERM, name: "SIGTERM"))
        #expect(DenIPCService.parseSignal("15") == .init(number: SIGTERM, name: "SIGTERM"))
        #expect(DenIPCService.parseSignal("INT") == .init(number: SIGINT, name: "SIGINT"))
        #expect(DenIPCService.parseSignal("SIGINT") == .init(number: SIGINT, name: "SIGINT"))
        #expect(DenIPCService.parseSignal("2") == .init(number: SIGINT, name: "SIGINT"))
        #expect(DenIPCService.parseSignal("KILL") == .init(number: SIGKILL, name: "SIGKILL"))
        #expect(DenIPCService.parseSignal("9") == .init(number: SIGKILL, name: "SIGKILL"))
        #expect(DenIPCService.parseSignal("HUP") == .init(number: SIGHUP, name: "SIGHUP"))
        #expect(DenIPCService.parseSignal("1") == .init(number: SIGHUP, name: "SIGHUP"))
        #expect(DenIPCService.parseSignal("UNKNOWN") == nil)
        #expect(DenIPCService.parseSignal("999") == nil)
    }
}
