import Foundation

/// Preview and operation tasks belong to the window, rather than the Profile's Board registry.
@MainActor
final class DenWindowResources {
    var drawerPreview: DrawerPreviewRuntime?
    var zmxCommandTask: Task<Void, Never>?
    var screenshotTask: Task<Void, Never>?

    func cancelTasks() {
        zmxCommandTask?.cancel()
        zmxCommandTask = nil
        screenshotTask?.cancel()
        screenshotTask = nil
    }
}
