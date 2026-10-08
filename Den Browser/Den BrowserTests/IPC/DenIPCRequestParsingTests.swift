import DenIPCProtocol
import Foundation
import Testing

@testable import Den_Browser

struct DenIPCRequestParsingTests {
    @Test func sheetGetPayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetGetAttributePayload(target: "#link", attribute: "href")
        let request = DenIPCRequest(
            operation: .sheet(
                command: .get(.attribute(payload)),
                target: .automatic
            ),
            context: DenIPCCallerContext(profileID: UUID(), callerBoardID: UUID())
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded == request)
    }

    @Test func sheetStatePayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetStatePayload(target: "input[type=checkbox]")
        let request = DenIPCRequest(
            operation: .sheetWithSnapshot(
                command: .isState(.checked(payload)),
                target: .explicit(UUID()),
                snapshot: DenSheetSnapshotPayload(full: true, within: "#main")
            )
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded == request)
    }

    @Test func sheetGetPayloadRejectsEmptyTarget() {
        #expect(throws: DenIPCInputError.self) {
            _ = try DenSheetGetTargetPayload(target: "")
        }
    }

    @Test func sheetGetAttributePayloadRejectsEmptyAttribute() {
        #expect(throws: DenIPCInputError.self) {
            _ = try DenSheetGetAttributePayload(target: "#link", attribute: "")
        }
    }

    @Test func sheetStatePayloadRejectsEmptyTarget() {
        #expect(throws: DenIPCInputError.self) {
            _ = try DenSheetStatePayload(target: "")
        }
    }

    @Test func interactStepRoundTripsWithTypedCommand() throws {
        let step = DenSheetInteractStep(
            line: 1,
            text: "click @e1",
            command: .click(
                DenSheetClickPayload(
                    target: "@e1",
                    role: nil,
                    name: nil,
                    exact: false,
                    newBoard: false,
                    focus: false
                )
            )
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(DenSheetInteractStep.self, from: data)

        #expect(decoded == step)
    }
}
