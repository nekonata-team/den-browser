import Foundation

nonisolated enum DenIPCInputError: Error, Equatable, LocalizedError, Sendable {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        }
    }
}

nonisolated struct DenIPCRequest: Codable, Sendable {
    var command: DenIPCCommand
    var boardID: String?
    var deskID: String?
    var callerBoardID: String?
    var profileID: String?
    var includeTargetContext: Bool?

    init(
        command: DenIPCCommand,
        boardID: String? = nil,
        deskID: String? = nil,
        callerBoardID: String? = nil,
        profileID: String? = nil,
        includeTargetContext: Bool? = nil
    ) {
        self.command = command
        self.boardID = boardID
        self.deskID = deskID
        self.callerBoardID = callerBoardID
        self.profileID = profileID
        self.includeTargetContext = includeTargetContext
    }

}
