import Foundation
import Observation

/// Opened Items keep one live runtime per Profile, independently of their presentation window.
@MainActor
@Observable
final class DenDrawerRuntimes {
    var web: [UUID: WebRuntime] = [:]
    var terminal: [UUID: TerminalRuntime] = [:]

    func dispose(_ itemID: UUID) {
        web.removeValue(forKey: itemID)?.dispose()
        terminal.removeValue(forKey: itemID)?.dispose()
    }

    func releaseWeb() {
        for runtime in web.values { runtime.dispose() }
        web.removeAll()
    }

    func releaseAll() {
        releaseWeb()
        for runtime in terminal.values { runtime.dispose() }
        terminal.removeAll()
    }
}
