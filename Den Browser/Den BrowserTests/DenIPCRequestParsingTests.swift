import Testing

@testable import Den_Browser

struct DenIPCRequestParsingTests {
    @Test func sheetGetPayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetGetPayload(kind: .attribute, target: "#link", attribute: "href")
        let request = DenIPCRequest(command: .sheet(.get), payload: .sheet(.get(payload)))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded.payload == request.payload)
    }

    @Test func sheetStatePayloadRoundTripsThroughRequest() throws {
        let payload = try DenSheetStatePayload(state: .checked, target: "input[type=checkbox]")
        let request = DenIPCRequest(command: .sheet(.isState), payload: .sheet(.isState(payload)))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DenIPCRequest.self, from: data)

        #expect(decoded.payload == request.payload)
    }

    @Test func sheetGetPayloadRejectsEmptyTarget() {
        #expect(throws: DenIPCInputError.self) {
            _ = try DenSheetGetPayload(kind: .text, target: "")
        }
    }

    @Test func sheetStatePayloadRejectsEmptyTarget() {
        #expect(throws: DenIPCInputError.self) {
            _ = try DenSheetStatePayload(state: .visible, target: "")
        }
    }
}
