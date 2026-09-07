import Foundation

nonisolated struct DenIPCRequest: Codable, Sendable {
    var command: String
    var args: [String] = []
    var boardID: String?
    var deskID: String?
    var callerBoardID: String?
}

nonisolated struct DenBoardInfo: Codable, Sendable {
    var id: String
    var type: String
    var label: String
    var url: String?
}

nonisolated struct DenDeskInfo: Codable, Sendable {
    var id: String
    var label: String
    var isActive: Bool
    var boardCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case isActive = "is_active"
        case boardCount = "board_count"
    }
}

nonisolated struct DenIPCResponse: Codable, Sendable {
    var isOk: Bool
    var error: String?
    var message: String?
    var boardId: String?
    var closedBoardId: String?
    var boards: [DenBoardInfo]?
    var desks: [DenDeskInfo]?
    var url: String?
    var snapshot: String?
    var text: String?
    var value: String?
    var screenshotPath: String?

    enum CodingKeys: String, CodingKey {
        case isOk = "ok"
        case error
        case message
        case boardId = "board_id"
        case closedBoardId = "closed_board_id"
        case boards
        case desks
        case url
        case snapshot
        case text
        case value
        case screenshotPath = "screenshot_path"
    }

    static func success(
        message: String? = nil,
        boardId: String? = nil,
        closedBoardId: String? = nil,
        boards: [DenBoardInfo]? = nil,
        desks: [DenDeskInfo]? = nil,
        url: String? = nil,
        snapshot: String? = nil,
        text: String? = nil,
        value: String? = nil,
        screenshotPath: String? = nil
    ) -> DenIPCResponse {
        DenIPCResponse(
            isOk: true,
            error: nil,
            message: message,
            boardId: boardId,
            closedBoardId: closedBoardId,
            boards: boards,
            desks: desks,
            url: url,
            snapshot: snapshot,
            text: text,
            value: value,
            screenshotPath: screenshotPath
        )
    }

    static func failure(_ error: String) -> DenIPCResponse {
        DenIPCResponse(
            isOk: false,
            error: error,
            message: nil,
            boardId: nil,
            closedBoardId: nil,
            boards: nil,
            desks: nil,
            url: nil,
            snapshot: nil,
            text: nil,
            value: nil,
            screenshotPath: nil
        )
    }
}
