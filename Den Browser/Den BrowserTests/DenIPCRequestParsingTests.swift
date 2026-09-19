import Testing

@testable import Den_Browser

struct DenIPCRequestParsingTests {
    @Test func sheetGetPayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetGetPayload(target: "#link", attribute: "href")
        let request = DenIPCRequest(command: .sheet(.get(.attribute)), payload: .sheet(.get(payload)))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded.command == request.command)
        #expect(decoded.payload == request.payload)
    }

    @Test func sheetStatePayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetStatePayload(target: "input[type=checkbox]")
        let request = DenIPCRequest(
            command: .sheet(.isState(.checked)),
            payload: .sheet(.isState(payload))
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded.command == request.command)
        #expect(decoded.payload == request.payload)
    }

    @Test func sheetGetPayloadRejectsEmptyTarget() {
        #expect(throws: DenIPCInputError.self) {
            _ = try DenSheetGetPayload(target: "")
        }
    }

    @Test func sheetStatePayloadRejectsEmptyTarget() {
        #expect(throws: DenIPCInputError.self) {
            _ = try DenSheetStatePayload(target: "")
        }
    }
}
