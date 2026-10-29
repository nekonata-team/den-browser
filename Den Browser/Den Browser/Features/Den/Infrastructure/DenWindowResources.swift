import Foundation

/// The window selects a Profile-owned Peek and owns its cancellable operation tasks.
@MainActor
final class DenWindowResources {
    var drawerPeek: WebRuntime?
    var drawerTerminalPeek: (itemID: UUID, runtime: TerminalRuntime)?
    var drawerItemID: UUID? { drawerPeek?.id ?? drawerTerminalPeek?.itemID }
    var zmxCommandTask: Task<Void, Never>?
    private var screenshotTask: Task<Void, Never>?
    private var screenshotTaskID: UUID?

    func startScreenshotOperation(_ operation: @escaping @MainActor () async -> Void) {
        screenshotTask?.cancel()
        let id = UUID()
        screenshotTaskID = id
        screenshotTask = Task { @MainActor [weak self] in
            defer {
                if self?.screenshotTaskID == id {
                    self?.screenshotTask = nil
                    self?.screenshotTaskID = nil
                }
            }
            await operation()
        }
    }

    func cancelTasks() {
        zmxCommandTask?.cancel()
        zmxCommandTask = nil
        screenshotTask?.cancel()
        screenshotTask = nil
        screenshotTaskID = nil
    }
}
