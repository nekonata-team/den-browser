import Testing

@testable import Den_Browser

@MainActor
struct DenIPCServiceTests {
    @Test func healthCommandReturnsHealthyWithoutAnActiveProfile() async {
        let service = DenIPCService()
        let response = await service.handleRequest(DenIPCRequest(command: .health))

        #expect(response.isOk)
        #expect(response.message == nil)
    }
}
