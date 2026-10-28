import Foundation
import Observation

/// Opened Items keep one live runtime per Profile, independently of their presentation window.
@MainActor
@Observable
final class DenDrawerRuntimes {
    var web: [UUID: WebRuntime] = [:]

    func dispose(_ itemID: UUID) {
        web.removeValue(forKey: itemID)?.dispose()
    }

    func releaseAll() {
        for runtime in web.values { runtime.dispose() }
        web.removeAll()
    }
}
