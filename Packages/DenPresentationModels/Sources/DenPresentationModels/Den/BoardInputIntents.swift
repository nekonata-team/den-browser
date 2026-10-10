import DenDomain
import Foundation

public struct BoardLinkFocusIntent: Equatable {
    public let id: UUID
    public let boardID: BoardID
    public let origin: BoardOperationOrigin

    public init(boardID: BoardID, origin: BoardOperationOrigin = .interactive) {
        id = UUID()
        self.boardID = boardID
        self.origin = origin
    }
}

public struct BoardRemovalIntent: Equatable {
    public let id: UUID
    public let origin: BoardOperationOrigin

    public init(origin: BoardOperationOrigin) {
        id = UUID()
        self.origin = origin
    }
}
