import Foundation
import Testing

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct UBOLiteInstallerTests {
    @Test func apiFailureDoesNotUseFixedFallback() async throws {
        let apiURL = try #require(URL(string: "https://ubolite.test/api/\(UUID().uuidString)"))
        StubURLProtocol.requestCount = 0
        StubURLProtocol.apiURL = apiURL
        StubURLProtocol.apiStatusCode = 503
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

    @Test func rejectsInvalidCandidateAndKeepsInstalledExtension() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try writeManifest(version: "2026.901.1442", to: directoryURL)
        try Data("keep".utf8).write(to: directoryURL.appending(path: "keep.txt"))

        let installer = try makeInstaller(
            directoryURL: directoryURL,
            candidateManifest: [
                "manifest_version": 2,
                "name": "uBlock Origin Lite",
                "version": "2026.920.1710",
            ])

        let success = await installer.install()

        #expect(!success)
        #expect(installer.installedVersion == "2026.901.1442")
        #expect(FileManager.default.fileExists(atPath: directoryURL.appending(path: "keep.txt").path))
    }

    @Test func rejectsOlderCandidateAndKeepsInstalledExtension() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try writeManifest(version: "2026.920.1710", to: directoryURL)

        let installer = try makeInstaller(
            directoryURL: directoryURL,
            candidateManifest: validManifest(version: "2026.901.1442"))

        let success = await installer.install()

        #expect(!success)
        #expect(installer.installedVersion == "2026.920.1710")
    }

    @Test func installsNewerCandidateWithValidManifest() async throws {
        let directoryURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try writeManifest(version: "2026.901.1442", to: directoryURL)

        let installer = try makeInstaller(
            directoryURL: directoryURL,
            candidateManifest: validManifest(version: "2026.920.1710"))

        let success = await installer.install()

        #expect(success)
        #expect(installer.installedVersion == "2026.920.1710")
    }

    private func makeInstaller(
        directoryURL: URL,
        candidateManifest: [String: Any]
    ) throws -> UBOLiteInstaller {
        let apiURL = try #require(URL(string: "https://ubolite.test/api/\(UUID().uuidString)"))
        let downloadURL = try #require(URL(string: "https://ubolite.test/download/\(UUID().uuidString).zip"))
        StubURLProtocol.apiURL = apiURL
        StubURLProtocol.apiStatusCode = 200
        StubURLProtocol.downloadStatusCode = 200
        StubURLProtocol.requestCount = 0
        StubURLProtocol.apiData = try JSONSerialization.data(withJSONObject: [
            "assets": [
                [
                    "name": "uBOLite_2026.920.1710.safari.zip",
                    "browser_download_url": downloadURL.absoluteString,
                ]
            ]
        ])
        StubURLProtocol.downloadData = Data("zip".utf8)
        let candidateManifestData = try JSONSerialization.data(withJSONObject: candidateManifest)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return UBOLiteInstaller(
            directoryURL: directoryURL,
            releaseAPIURL: apiURL,
            session: URLSession(configuration: configuration),
            commandRunner: ArchiveCommandRunner(manifest: candidateManifestData))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "ubolite-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func writeManifest(version: String, to directoryURL: URL) throws {
        try JSONSerialization.data(withJSONObject: validManifest(version: version))
            .write(to: directoryURL.appending(path: "manifest.json"))
    }

    private func validManifest(version: String) -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "uBlock Origin Lite",
            "version": version,
            "background": ["scripts": ["/js/background.js"]],
        ]
    }
}

private struct ArchiveCommandRunner: TerminalCommandRunning, Sendable {
    let manifest: Data

    func run(
        executablePath: String,
        arguments: [String],
        timeout: Duration
    ) async throws -> TerminalCommandResult {
        guard arguments.count == 4 else {
            throw TerminalCommandError(message: "Unexpected archive arguments")
        }
        let directoryURL = URL(fileURLWithPath: arguments[3])
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try manifest.write(to: directoryURL.appending(path: "manifest.json"))
        return TerminalCommandResult(terminationStatus: 0, standardOutput: "")
    }
}

private class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0
    nonisolated(unsafe) static var apiURL: URL?
    nonisolated(unsafe) static var apiStatusCode = 503
    nonisolated(unsafe) static var downloadStatusCode = 200
    nonisolated(unsafe) static var apiData = Data()
    nonisolated(unsafe) static var downloadData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let isAPI = url == Self.apiURL
        let response = HTTPURLResponse(
            url: url,
            statusCode: isAPI ? Self.apiStatusCode : Self.downloadStatusCode,
            httpVersion: nil,
            headerFields: nil)
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let data = isAPI ? Self.apiData : Self.downloadData
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
