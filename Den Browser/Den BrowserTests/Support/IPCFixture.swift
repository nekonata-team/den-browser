import DenDomain
import DenIPCProtocol
import DenModels
import Foundation
import Testing

@testable import Den_Browser

func makeIPCRequest(
    _ operation: DenIPCOperation,
    profileID: UUID? = nil,
    callerBoardID: UUID? = nil
) -> DenIPCRequest {
    DenIPCRequest(
        operation: operation,
        context: DenIPCCallerContext(profileID: profileID, callerBoardID: callerBoardID)
    )
}

func extractCreatedBoardID(_ response: DenIPCOperationResult) throws -> BoardID {
    let id: String
    if case .createdBoard(let boardID, _, _) = response.payload {
        id = boardID
    } else {
        Issue.record("Expected created Board payload")
        id = ""
    }
    return BoardID(try #require(UUID(uuidString: id)))
}

extension DenIPCService {
    func handleResult(_ request: DenIPCRequest) async -> DenIPCOperationResult {
        await handleRequest(request).result
    }
}
