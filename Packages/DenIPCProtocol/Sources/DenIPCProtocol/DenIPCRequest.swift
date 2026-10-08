import Foundation

public nonisolated enum DenIPCInputError: Error, Equatable, LocalizedError, Sendable {
    case usage(String)

    public var errorDescription: String? {
        switch self {
        case .usage(let message): message
        }
    }
}

public nonisolated enum BoardTarget: Codable, Equatable, Sendable {
    case automatic
    case explicit(UUID)
}

public nonisolated enum DeskTarget: Codable, Equatable, Sendable {
    case automatic
    case explicit(UUID)
}

public nonisolated struct DenIPCCallerContext: Codable, Equatable, Sendable {
    public var profileID: UUID?
    public var callerBoardID: UUID?

    public init(profileID: UUID? = nil, callerBoardID: UUID? = nil) {
        self.profileID = profileID
        self.callerBoardID = callerBoardID
    }
}

/// The operation sent over the private, same-version app/CLI IPC connection.
public nonisolated enum DenIPCOperation: Codable, Equatable, Sendable {
    case sheet(command: DenIPCCommand.Sheet, target: BoardTarget)
    case sheetWithSnapshot(command: DenIPCCommand.Sheet, target: BoardTarget, snapshot: DenSheetSnapshotPayload)
    case boardList(target: DeskTarget)
    case boardFocused(target: DeskTarget)
    case boardClose(target: BoardTarget)
    case createWebBoard(payload: DenBoardWebNewPayload, destination: DeskTarget)
    case createTerminalBoard(payload: DenBoardTerminalNewPayload, destination: DeskTarget)
    case createInspectionBoard(targetBoardID: UUID, payload: DenBoardInspectionNewPayload)
    case deskList(target: DeskTarget)
    case drawer(command: DenIPCCommand.Drawer, target: DeskTarget)
    case terminal(command: DenIPCCommand.Terminal, target: BoardTarget)
    case readInspection(boardID: UUID)
    case profileList
    case openProfile(profileID: UUID)
    case inspectDen(target: DeskTarget)
    case health
}

public nonisolated struct DenIPCRequest: Codable, Equatable, Sendable {
    public var operation: DenIPCOperation
    public var context: DenIPCCallerContext

    public init(
        operation: DenIPCOperation,
        context: DenIPCCallerContext = DenIPCCallerContext()
    ) {
        self.operation = operation
        self.context = context
    }
}
