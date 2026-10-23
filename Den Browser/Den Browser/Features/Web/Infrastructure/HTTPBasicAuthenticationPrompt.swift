import AppKit
import SwiftUI
import WebKit

@MainActor
final class HTTPBasicAuthenticationPrompt {
    let id: UUID
    weak var webView: WKWebView?
    private let challenge: URLAuthenticationChallenge
    private var completion: (@MainActor (URLCredential?) -> Void)?
    private var hostingView: NSView?

    init(
        id: UUID, challenge: URLAuthenticationChallenge, webView: WKWebView,
        completion: @escaping @MainActor (URLCredential?) -> Void
    ) {
        self.id = id
        self.challenge = challenge
        self.webView = webView
        self.completion = completion
    }

    func present() {
        guard hostingView == nil, completion != nil else { return }
        guard let webView else {
            finish(nil)
            return
        }
        // Anchor the SwiftUI alert to the WebView's current window, including auxiliary windows.
        let host = NSHostingView(
            rootView: HTTPBasicAuthenticationAlert(challenge: challenge) { [weak self] in self?.finish($0) })
        hostingView = host
        webView.addSubview(host)
    }

    func finish(_ credential: URLCredential?) {
        guard let completion else { return }
        self.completion = nil
        hostingView?.removeFromSuperview()
        hostingView = nil
        completion(credential)
    }
}

private struct HTTPBasicAuthenticationAlert: View {
    let challenge: URLAuthenticationChallenge
    let complete: @MainActor (URLCredential?) -> Void
    @State private var isPresented = false
    @State private var username: String
    @State private var password = ""

    init(challenge: URLAuthenticationChallenge, complete: @escaping @MainActor (URLCredential?) -> Void) {
        self.challenge = challenge
        self.complete = complete
        _username = State(initialValue: challenge.proposedCredential?.user ?? "")
    }

    private var message: String {
        let message =
            challenge.previousFailureCount > 0
            ? "The username or password was not accepted. Try again."
            : "Enter your username and password."
        return message + (challenge.protectionSpace.protocol == "http" ? "\nThis connection is not encrypted." : "")
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .alert(
                "Sign in to \(challenge.protectionSpace.host):\(String(challenge.protectionSpace.port))",
                isPresented: $isPresented
            ) {
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                Button("Sign In") {
                    complete(URLCredential(user: username, password: password, persistence: .none))
                }
                Button("Cancel", role: .cancel) { complete(nil) }
            } message: {
                Text(message)
            }
            .onAppear { isPresented = true }
            .onDisappear { complete(nil) }
    }
}
