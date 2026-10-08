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
            result: .success(.createdBoard(id: createdBoardID.uuidString, message: nil, url: nil)),
            target: .board(profileID: profileID, boardID: targetBoardID)
        )

        // Act
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DenIPCResponse.self, from: data)

        // Assert
        #expect(decoded.result.isOk)
        if case .createdBoard(let id, _, _) = decoded.result.payload {
            #expect(id == createdBoardID.uuidString)
        } else {
            Issue.record("Expected created Board result payload")
        }
        if case .board(let decodedProfileID, let decodedBoardID) = decoded.target {
            #expect(decodedProfileID == profileID)
            #expect(decodedBoardID == targetBoardID)
        } else {
            Issue.record("Expected a board target context")
        }
    }

    @Test func responseFailureRoundTripsRetainedProgressAndSnapshot() throws {
        // Arrange
        let response = DenIPCResponse(
            result: .failure(
                "Element not found",
                payload: .interaction(completedActions: 1, failedActionIndex: 1),
                snapshot: "button \"Continue\""),
            target: .none)

        // Act
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(DenIPCResponse.self, from: data)

        // Assert
        #expect(decoded.result.isOk == false)
        #expect(decoded.result.error == "Element not found")
        #expect(decoded.result.snapshot == "button \"Continue\"")
        #expect(decoded.result.completedActions == 1)
        #expect(decoded.result.failedActionIndex == 1)
    }
}
