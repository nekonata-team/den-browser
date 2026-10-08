import DenIPCProtocol
import Foundation
import Testing

struct DenIPCRequestTests {
    @Test func operationUnionRoundTripsWithTypedTargetsAndContext() throws {
        // Arrange
        let profileID = UUID()
        let boardID = UUID()
        let request = DenIPCRequest(
            operation: .sheetWithSnapshot(
                command: .url,
                target: .explicit(boardID),
                snapshot: DenSheetSnapshotPayload(full: true)
            ),
            context: DenIPCCallerContext(profileID: profileID, callerBoardID: UUID())
        )

        // Act
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        // Assert
        #expect(decoded == request)
    }

    @Test func inspectionAndProfileOperationsRequireTheirIDs() throws {
        // Arrange
        let missingInspectionID = Data(
            #"{"operation":{"readInspection":{}},"context":{}}"#.utf8
        )
        let missingProfileID = Data(
            #"{"operation":{"openProfile":{}},"context":{}}"#.utf8
        )

        // Act
        var inspectionFailure: Error?
        do {
            _ = try JSONDecoder().decode(DenIPCRequest.self, from: missingInspectionID)
        } catch {
            inspectionFailure = error
        }
        var profileFailure: Error?
        do {
            _ = try JSONDecoder().decode(DenIPCRequest.self, from: missingProfileID)
        } catch {
            profileFailure = error
        }

        // Assert
        #expect(inspectionFailure is DecodingError)
        #expect(profileFailure is DecodingError)
    }

    @Test func responseCarriesOneResolvedTargetContext() throws {
        // Arrange
        let profileID = UUID()
        let targetBoardID = UUID()
        let createdBoardID = UUID()
        let response = DenIPCResponse(
            result: .success(boardId: createdBoardID.uuidString),
            target: .board(profileID: profileID, boardID: targetBoardID)
        )

        // Act
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DenIPCResponse.self, from: data)

        // Assert
        #expect(decoded.result.isOk)
        #expect(decoded.result.boardId == createdBoardID.uuidString)
        if case .board(let decodedProfileID, let decodedBoardID) = decoded.target {
            #expect(decodedProfileID == profileID)
            #expect(decodedBoardID == targetBoardID)
        } else {
            Issue.record("Expected a board target context")
        }
    }
}
