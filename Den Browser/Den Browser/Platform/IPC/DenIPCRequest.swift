import Foundation

nonisolated enum DenIPCInputError: Error, Equatable, LocalizedError, Sendable {
    case usage(String)
    case legacyArguments

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        case .legacyArguments:
            "The IPC request field 'args' is no longer supported; use 'payload'"
        }
    }
}

nonisolated struct DenIPCRequest: Codable, Sendable {
    var command: DenIPCCommand
    var payload: DenIPCRequestPayload?
    var boardID: String?
    var deskID: String?
    var callerBoardID: String?
    var profileID: String?

    init(
        command: DenIPCCommand,
        payload: DenIPCRequestPayload? = nil,
        boardID: String? = nil,
        deskID: String? = nil,
        callerBoardID: String? = nil,
        profileID: String? = nil
    ) {
        self.command = command
        self.payload = payload
        self.boardID = boardID
        self.deskID = deskID
        self.callerBoardID = callerBoardID
        self.profileID = profileID
    }

    enum CodingKeys: String, CodingKey {
        case command
        case payload
        case boardID
        case deskID
        case callerBoardID
        case profileID
        case args
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.args) {
            throw DenIPCInputError.legacyArguments
        }
        command = try container.decode(DenIPCCommand.self, forKey: .command)
        payload = try container.decodeIfPresent(DenIPCRequestPayload.self, forKey: .payload)
        boardID = try container.decodeIfPresent(String.self, forKey: .boardID)
        deskID = try container.decodeIfPresent(String.self, forKey: .deskID)
        callerBoardID = try container.decodeIfPresent(String.self, forKey: .callerBoardID)
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(boardID, forKey: .boardID)
        try container.encodeIfPresent(deskID, forKey: .deskID)
        try container.encodeIfPresent(callerBoardID, forKey: .callerBoardID)
        try container.encodeIfPresent(profileID, forKey: .profileID)
    }
}
