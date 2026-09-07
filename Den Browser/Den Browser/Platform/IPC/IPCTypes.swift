import Foundation

nonisolated struct DenIPCRequest: Codable, Sendable {
    var command: String
    var args: [String] = []
    var boardID: String?
    var deskID: String?
    var callerBoardID: String?
}

nonisolated struct DenIPCResponse: Codable, Sendable {
    var success: Bool
    var result: String?
    var error: String?

    static func success(_ result: String?) -> DenIPCResponse {
        DenIPCResponse(success: true, result: result, error: nil)
    }

    static func failure(_ message: String) -> DenIPCResponse {
        DenIPCResponse(success: false, result: nil, error: message)
    }
}
