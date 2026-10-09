import DenDomain
import Foundation
import Observation

/// Profile-owned Board runtimes survive individual window lifetimes.
@MainActor
@Observable
final class DenBoardRuntimes {
    var web: [BoardID: WebBoardRuntime] = [:]
    @ObservationIgnored var terminal: [BoardID: TerminalRuntime] = [:]
    @ObservationIgnored private let onDispose: (BoardID) -> Void

    init(onDispose: @escaping (BoardID) -> Void) {
        self.onDispose = onDispose
    }

    func releaseWeb() {
        for (boardID, runtime) in web {
            onDispose(boardID)
            runtime.dispose()
        }
        web.removeAll()
    }

    func releaseTerminal() {
        for (boardID, runtime) in terminal {
            onDispose(boardID)
            runtime.dispose()
        }
        terminal.removeAll()
    }

    func dispose(_ boardID: BoardID) {
        onDispose(boardID)
        web.removeValue(forKey: boardID)?.dispose()
        terminal.removeValue(forKey: boardID)?.dispose()
    }
}
