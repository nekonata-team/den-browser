import Foundation
import Network
import Testing
import WebKit

@testable import Den_Browser

@MainActor
@Suite(.serialized)
struct HTTPBasicAuthenticationTests {
    @Test(.timeLimit(.minutes(1)))
    func retriesRejectedCredentialsAndLoadsTheProtectedPage() async throws {
        // Arrange
        let server = try BasicAuthenticationServer()
        defer { server.stop() }
        let url = try await server.start()
        let runtime = makeRuntime()
        defer { runtime.dispose() }
        runtime.credentials = [
            URLCredential(user: "user", password: "incorrect", persistence: .none),
            URLCredential(user: "user", password: "password", persistence: .none),
        ]

        // Act
        let result = await runtime.navigate(to: url)

        // Assert
        try result.get()
        #expect(runtime.failureCounts == [0, 1])
        #expect(try await runtime.webView.evaluateJavaScript("document.body.innerText") as? String == "Authenticated")
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingThePromptLeavesTheUnauthorizedPage() async throws {
        // Arrange
        let server = try BasicAuthenticationServer()
        defer { server.stop() }
        let url = try await server.start()
        let runtime = makeRuntime()
        defer { runtime.dispose() }

        // Act
        let result = await runtime.navigate(to: url)

        // Assert
        try result.get()
        #expect(runtime.failureCounts == [0])
        #expect(
            try await runtime.webView.evaluateJavaScript("document.body.innerText") as? String
                == "Authentication required")
    }

    @Test(arguments: [NSURLAuthenticationMethodServerTrust, NSURLAuthenticationMethodHTTPDigest])
    func otherAuthenticationMethodsUseSystemHandling(method: String) {
        // Arrange
        let runtime = makeRuntime()
        defer { runtime.dispose() }
        let space = URLProtectionSpace(
            host: "example.com", port: 443, protocol: "https", realm: nil, authenticationMethod: method)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: AuthenticationChallengeSender())
        var dispositions: [URLSession.AuthChallengeDisposition] = []

        // Act
        runtime.webView(runtime.webView, didReceive: challenge) { disposition, credential in
            dispositions.append(disposition)
            #expect(credential == nil)
        }

        // Assert
        #expect(dispositions == [.performDefaultHandling])
        #expect(runtime.failureCounts.isEmpty)
    }

    @Test(arguments: ["dispose", "navigation", "close", "termination"])
    func endingTheWebPresentationCancelsQueuedChallengesOnce(event: String) {
        // Arrange
        let runtime = BaseWebRuntime(
            id: UUID(), initialURL: nil, websiteDataStore: .nonPersistent(),
            userContentController: nil, sheetScale: 100)
        let space = URLProtectionSpace(
            host: "example.com", port: 443, protocol: "https", realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: AuthenticationChallengeSender())
        var dispositions: [URLSession.AuthChallengeDisposition] = []
        for _ in 0..<2 {
            runtime.webView(runtime.webView, didReceive: challenge) { disposition, credential in
                dispositions.append(disposition)
                #expect(credential == nil)
            }
        }

        // Act
        switch event {
        case "navigation": runtime.webView(runtime.webView, didStartProvisionalNavigation: nil)
        case "close": runtime.webViewDidClose(runtime.webView)
        case "termination": runtime.webViewWebContentProcessDidTerminate(runtime.webView)
        default: runtime.dispose()
        }
        runtime.dispose()

        // Assert
        #expect(dispositions == [.cancelAuthenticationChallenge, .cancelAuthenticationChallenge])
    }

    private func makeRuntime() -> AuthenticationRuntime {
        AuthenticationRuntime(
            id: UUID(), initialURL: nil, websiteDataStore: .nonPersistent(),
            userContentController: nil, sheetScale: 100)
    }
}

@MainActor
private final class AuthenticationRuntime: BaseWebRuntime {
    var credentials: [URLCredential] = []
    var failureCounts: [Int] = []
    private var navigationCompletion: CheckedContinuation<Result<Void, Error>, Never>?

    func navigate(to url: URL) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            navigationCompletion = continuation
            load(url)
        }
    }

    override func requestHTTPBasicCredential(
        for challenge: URLAuthenticationChallenge, in webView: WKWebView,
        completion: @escaping @MainActor (URLCredential?) -> Void
    ) {
        failureCounts.append(challenge.previousFailureCount)
        completion(credentials.isEmpty ? nil : credentials.removeFirst())
    }

    override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        complete(.success(()))
    }

    override func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(.failure(error))
    }

    override func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        complete(.failure(error))
    }

    private func complete(_ result: Result<Void, Error>) {
        navigationCompletion?.resume(returning: result)
        navigationCompletion = nil
    }
}

private final class AuthenticationChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}

private final class BasicAuthenticationServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "HTTPBasicAuthenticationTests")

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            Self.receive(connection, data: Data())
        }
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/")!)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { chunk, _, complete, error in
            let data = data + (chunk ?? Data())
            guard let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            guard request.contains("\r\n\r\n") else {
                if complete || error != nil {
                    connection.cancel()
                } else {
                    receive(connection, data: data)
                }
                return
            }
            let expectedAuthorization = Data("user:password".utf8).base64EncodedString()
            let authorization = request.components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("authorization:") }?
                .split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
            let authenticated = authorization == "Basic \(expectedAuthorization)"
            let body = authenticated ? "Authenticated" : "Authentication required"
            let status = authenticated ? "200 OK" : "401 Unauthorized"
            let challenge = authenticated ? "" : "WWW-Authenticate: Basic realm=\"Local fixture\"\r\n"
            let response =
                "HTTP/1.1 \(status)\r\n\(challenge)Content-Type: text/html\r\n"
                + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
