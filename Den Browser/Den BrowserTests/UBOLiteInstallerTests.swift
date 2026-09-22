import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct UBOLiteInstallerTests {
    @Test func apiFailureDoesNotUseFixedFallback() async throws {
        let apiURL = try #require(URL(string: "https://ubolite.test/api/\(UUID().uuidString)"))
        StubURLProtocol.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/MV3Extension", directoryHint: .isDirectory)
        let installer = UBOLiteInstaller(
            directoryURL: fixtureURL,
            releaseAPIURL: apiURL,
            session: session)

        let success = await installer.install()

        #expect(!success)
        #expect(StubURLProtocol.requestCount == 1)
        #expect(installer.isInstalled)
        #expect(installer.installedVersion == "1.0.0")

        let newInstaller = UBOLiteInstaller(
            directoryURL: FileManager.default.temporaryDirectory
                .appending(path: "ubolite-missing-\(UUID().uuidString)", directoryHint: .isDirectory),
            releaseAPIURL: apiURL,
            session: session)
        let newInstallSuccess = await newInstaller.install()

        #expect(!newInstallSuccess)
        #expect(StubURLProtocol.requestCount == 2)
        #expect(!newInstaller.isInstalled)
    }
}

private class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
