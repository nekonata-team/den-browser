import Foundation

public nonisolated enum DenIPCInputError: Error, Equatable, LocalizedError, Sendable {
    case usage(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        }
    }
}

public nonisolated struct DenIPCRequest: Codable, Sendable {
    public var command: DenIPCCommand
    public var boardID: String?
    public var deskID: String?
    public var callerBoardID: String?
    public var profileID: String?
    public var includeTargetContext: Bool?
    public var includeSnapshot: Bool?

    public init(
        command: DenIPCCommand,
        boardID: String? = nil,
        deskID: String? = nil,
        callerBoardID: String? = nil,
        profileID: String? = nil,
        includeTargetContext: Bool? = nil,
        includeSnapshot: Bool? = nil
    ) {
        self.command = command
        self.boardID = boardID
        self.deskID = deskID
        self.callerBoardID = callerBoardID
        self.profileID = profileID
        self.includeTargetContext = includeTargetContext
        self.includeSnapshot = includeSnapshot
    }

}
