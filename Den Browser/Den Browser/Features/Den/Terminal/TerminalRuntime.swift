import AppKit
import Combine
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
        var onLinkActivated: () -> Void = {}
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

    init(workingDirectory: String, command: String? = nil, events: Events) {
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
        terminalView.configuration = TerminalSurfaceOptions(
            workingDirectory: workingDirectory,
            context: .window)
        terminalView.controller = controller
    }

    func updateOwner(events: Events) {
        self.events = events
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
        events.onLinkActivated()
        events.onOpenURL(url)
    }
}

extension TerminalRuntime: TerminalSurfaceDesktopNotificationDelegate {
    func terminalDidRequestDesktopNotification(title: String, body: String) {
        guard !isDisposed else { return }
        events.onNotification(title, body)
    }
}
