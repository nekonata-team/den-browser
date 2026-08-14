import AppKit
import Combine
import GhosttyTerminal

@MainActor
final class TerminalRuntime: NSObject, ObservableObject {
    struct Events {
        var onClose: () -> Void
        var onFocus: () -> Void
        var onWorkingDirectoryChange: (String) -> Void
        var onTitleChange: (String) -> Void
        var onOpenURL: (String) -> Void
        var onNotification: (String) -> Void
    }

    let terminalView: AppTerminalView
    private var controller: TerminalController?
    private var events: Events
    private var isDisposed = false
    private var isCloseNotificationScheduled = false

    init(workingDirectory: String, command: String? = nil, events: Events) {
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

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        terminalView.setSurfaceVisible(false)
        terminalView.delegate = nil
        terminalView.controller = nil
        controller = nil
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
        events.onNotification([title, body].filter { !$0.isEmpty }.joined(separator: ": "))
    }
}
