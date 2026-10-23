import DenDomain
import Foundation

@MainActor
final class RuntimeWindowConnection {
    weak var controller: DenController?
    var presentedDeskID: () -> DeskID? = { nil }
    var focusedBoardID: () -> BoardID? = { nil }

    var onDisconnect: () -> Void = {}

    func disconnect() {
        onDisconnect()
        presentedDeskID = { nil }
        focusedBoardID = { nil }
        controller = nil
    }
}
