import AppKit
import Combine
import GhosttyKit
import GhosttyTerminal

@MainActor
final class TerminalRuntime: NSObject, ObservableObject {
    struct CommandResult: Equatable {
        let exitCode: Int?
        let durationNanos: UInt64
    }

    struct Events {
        var onClose: () -> Void
        var onFocus: () -> Void
        var onWorkingDirectoryChange: (String) -> Void
        var onTitleChange: (String) -> Void
        var onOpenURL: (String) -> Void
        var onNotification: (String, String) -> Void
    }

    let terminalView: AppTerminalView
    @Published private(set) var progressState: TerminalProgressState?
    @Published private(set) var progressPercent: Int?
    @Published private(set) var lastCommandResult: CommandResult?
    @Published private(set) var lastBellDate: Date?
    var foregroundProcessGroupID: pid_t? { terminalView.foregroundPid }
    private var controller: TerminalController?
    private var events: Events
    private var hiddenTickTask: Task<Void, Never>?
    private var isDisposed = false
    private var isCloseNotificationScheduled = false
    private var isSurfaceVisible = true

    // Keep libghostty app_tick processing while the surface's display link is paused.
    private static let hiddenTickInterval = Duration.seconds(1)

    init(workingDirectory: String, command: String? = nil, boardID: UUID? = nil, events: Events) {
        PerformanceTrace.mark("TerminalRuntime.init (dir: \(workingDirectory))", category: "Terminal")
        self.events = events
        terminalView = AppTerminalView(frame: .zero)
        super.init()
        let resolution = TerminalConfigurationSource.make(commandOverride: command)
        let controller = TerminalController(
            configSource: resolution.configSource,
            theme: resolution.theme)
        self.controller = controller
        terminalView.delegate = self

        var envVars: [String: String] = [:]
        if let boardID {
            envVars["DEN_BOARD_ID"] = boardID.uuidString
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            envVars["DEN_SOCKET"] = "\(home)/.den/den.sock"
        }

        terminalView.configuration = TerminalSurfaceOptions(
            workingDirectory: workingDirectory,
            envVars: envVars,
            context: .window)
        terminalView.controller = controller
    }

    func updateOwner(events: Events) {
        self.events = events
    }

    func sendText(_ text: String) {
        terminalView.sendText(text)
    }

    func runCommand(_ command: String) {
        terminalView.sendText(command)

        let timestamp = ProcessInfo.processInfo.systemUptime
        let windowNumber = terminalView.window?.windowNumber ?? 0
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
        if let event {
            terminalView.keyDown(with: event)
        }

        let keyUp = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
        if let keyUp {
            terminalView.keyUp(with: keyUp)
        }
    }

    struct SignalError: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }

    func sendSignal(_ signal: Int32) throws -> pid_t {
        guard let pid = foregroundProcessGroupID, pid > 1, pid != getpid() else {
            throw SignalError("No foreground process found to signal")
        }
        if killpg(pid, signal) == 0 {
            return pid
        }
        if kill(pid, signal) == 0 {
            return pid
        }
        let err = String(cString: strerror(errno))
        throw SignalError("Failed to send signal \(signal) to process \(pid): \(err)")
    }

    func readViewportText() -> String? {
        guard let surface = rawGhosttySurface else { return nil }
        let topLeft = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0,
            y: 0
        )
        let bottomRight = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: 0,
            y: 0
        )
        let selection = ghostty_selection_s(
            top_left: topLeft,
            bottom_right: bottomRight,
            rectangle: false
        )

        var out = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &out) else {
            return nil
        }
        defer { ghostty_surface_free_text(surface, &out) }

        guard let textPtr = out.text, out.text_len > 0 else {
            return ""
        }
        let bytes = UnsafeBufferPointer(start: textPtr, count: Int(out.text_len))
            .map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private var rawGhosttySurface: ghostty_surface_t? {
        for coreChild in Mirror(reflecting: terminalView).children where coreChild.label == "core" {
            for surfaceChild in Mirror(reflecting: coreChild.value).children where surfaceChild.label == "surface" {
                if let surfaceObj = surfaceChild.value as? TerminalSurface {
                    for ptrChild in Mirror(reflecting: surfaceObj).children where ptrChild.label == "surface" {
                        if let ptr = ptrChild.value as? ghostty_surface_t {
                            return ptr
                        }
                    }
                }
            }
        }
        return nil
    }

    func setSurfaceVisible(_ visible: Bool) {
        guard !isDisposed, isSurfaceVisible != visible else { return }
        isSurfaceVisible = visible
        if visible {
            stopHiddenTicking()
        } else {
            startHiddenTicking()
        }
        terminalView.setSurfaceVisible(visible)
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        stopHiddenTicking()
        terminalView.setSurfaceVisible(false)
        terminalView.delegate = nil
        terminalView.controller = nil
        controller = nil
    }

    private func startHiddenTicking() {
        guard hiddenTickTask == nil else { return }
        hiddenTickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.isDisposed else { return }
                self.controller?.tick()
                try? await Task.sleep(for: Self.hiddenTickInterval)
            }
        }
    }

    private func stopHiddenTicking() {
        hiddenTickTask?.cancel()
        hiddenTickTask = nil
    }
}

extension TerminalRuntime: TerminalSurfaceCloseDelegate {
    func terminalDidClose(processAlive _: Bool) {
        guard !isDisposed, !isCloseNotificationScheduled else { return }
        isCloseNotificationScheduled = true
        // Ghostty invokes close callbacks from app_tick; let it unwind before teardown.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDisposed else { return }
            self.events.onClose()
        }
    }
}

extension TerminalRuntime: TerminalSurfaceFocusDelegate {
    func terminalDidChangeFocus(_ focused: Bool) {
        if focused, !isDisposed { events.onFocus() }
    }
}

extension TerminalRuntime: TerminalSurfaceBellDelegate {
    func terminalDidRingBell() {
        guard !isDisposed else { return }
        lastBellDate = Date()
    }
}

extension TerminalRuntime: TerminalSurfaceProgressReportDelegate {
    func terminalDidReportProgress(state: TerminalProgressState, percent: Int?) {
        guard !isDisposed else { return }
        switch state {
        case .remove:
            progressState = nil
            progressPercent = nil
        case .set, .error, .indeterminate, .pause:
            progressState = state
            progressPercent = percent
        }
    }
}

extension TerminalRuntime: TerminalSurfaceCommandFinishedDelegate {
    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        guard !isDisposed else { return }
        lastCommandResult = CommandResult(exitCode: exitCode, durationNanos: durationNanos)
    }
}

extension TerminalRuntime: TerminalSurfacePwdDelegate {
    func terminalDidChangeWorkingDirectory(_ path: String) {
        guard !isDisposed else { return }
        events.onWorkingDirectoryChange(path)
    }
}

extension TerminalRuntime: TerminalSurfaceTitleDelegate {
    func terminalDidChangeTitle(_ title: String) {
        guard !isDisposed else { return }
        events.onTitleChange(title)
    }
}

extension TerminalRuntime: TerminalSurfaceOpenURLDelegate {
    func terminalDidRequestOpenURL(_ url: String, kind _: TerminalOpenURLKind) {
        guard !isDisposed else { return }
        events.onOpenURL(url)
    }
}

extension TerminalRuntime: TerminalSurfaceDesktopNotificationDelegate {
    func terminalDidRequestDesktopNotification(title: String, body: String) {
        guard !isDisposed else { return }
        events.onNotification(title, body)
    }
}
