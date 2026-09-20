import Foundation
import Testing

@testable import Den_Browser

struct DenIPCRequestParsingTests {
    @Test func sheetGetPayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetGetAttributePayload(target: "#link", attribute: "href")
        let request = DenIPCRequest(command: .sheet(.get(.attribute(payload))))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded.command == request.command)
    }

    @Test func sheetStatePayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetStatePayload(target: "input[type=checkbox]")
        let request = DenIPCRequest(
            command: .sheet(.isState(.checked(payload)))
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded.command == request.command)
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
