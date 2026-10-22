import DenDomain
import Foundation
import Observation

/// Profile-owned Board runtimes survive individual window lifetimes.
@MainActor
@Observable
final class DenBoardRuntimes {
    var web: [BoardID: WebRuntime] = [:]
    @ObservationIgnored var terminal: [BoardID: TerminalRuntime] = [:]
    @ObservationIgnored var receivers: [BoardID: BoardRuntimeReceiver] = [:]

    func releaseWeb() {
        for (boardID, runtime) in web {
            receivers.removeValue(forKey: boardID)
            runtime.dispose()
        }
        web.removeAll()
    }

    func releaseTerminal() {
        for (boardID, runtime) in terminal {
            receivers.removeValue(forKey: boardID)
            runtime.dispose()
        }
        terminal.removeAll()
    }

    func dispose(_ boardID: BoardID) {
        receivers.removeValue(forKey: boardID)
        web.removeValue(forKey: boardID)?.dispose()
        terminal.removeValue(forKey: boardID)?.dispose()
    }
}
