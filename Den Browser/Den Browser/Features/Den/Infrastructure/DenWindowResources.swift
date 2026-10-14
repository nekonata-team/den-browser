import Foundation

/// Peek and operation tasks belong to the window, rather than the Profile's Board registry.
@MainActor
final class DenWindowResources {
    var drawerPeek: WebRuntime?
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
