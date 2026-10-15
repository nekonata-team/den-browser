import DenDomain
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct WebRuntimeHTTPStatusTests {
    @Test(arguments: [200, 404, 500], [false, true])
    func recordsMainPageHTTPStatusAfterLoading(status: Int, loading: Bool) {
        // Arrange
        let webView = StatusWebView(frame: .zero, configuration: configuration())
        let runtime = makeRuntime(webView: webView)
        defer { runtime.dispose() }

        // Act
        webView.simulatesLoading = loading
        runtime.recordHTTPStatus(status, isMainFrame: true, in: webView)

        // Assert
        #expect(runtime.httpStatusCode == (loading ? nil : status))
    }

    @Test(arguments: ["iframe", "popup"])
    func ignoresResponsesOutsideTheDisplayedMainPage(kind: String) {
        // Arrange
        let webView = StatusWebView(frame: .zero, configuration: configuration())
        let runtime = makeRuntime(webView: webView)
        defer { runtime.dispose() }
        runtime.recordHTTPStatus(200, isMainFrame: true, in: webView)
        let targetWebView = kind == "popup" ? StatusWebView(frame: .zero, configuration: configuration()) : webView

        // Act
        runtime.recordHTTPStatus(503, isMainFrame: kind != "iframe", in: targetWebView)

        // Assert
        #expect(runtime.httpStatusCode == 200)
    }

    @Test(arguments: ["navigation", "failure", "provisionalFailure", "termination", "nonHTTP"])
    func clearsPreviousHTTPStatusWhenItBecomesUnavailable(event: String) {
        // Arrange
        let webView = StatusWebView(frame: .zero, configuration: configuration())
        let runtime = makeRuntime(webView: webView)
        defer { runtime.dispose() }
        runtime.recordHTTPStatus(200, isMainFrame: true, in: webView)
        let error = URLError(.cannotConnectToHost)

        // Act
        switch event {
        case "navigation": runtime.webView(webView, didStartProvisionalNavigation: nil)
        case "failure": runtime.webView(webView, didFail: nil, withError: error)
        case "provisionalFailure": runtime.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        case "termination": runtime.webViewWebContentProcessDidTerminate(webView)
        default:
            runtime.recordHTTPStatus(nil, isMainFrame: true, in: webView)
        }

        // Assert
        #expect(runtime.httpStatusCode == nil)
    }

    private func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }

    private func makeRuntime(webView: WKWebView) -> WebRuntime {
        WebRuntime(
            board: BoardState(label: "Page", width: 520, currentSheetURL: nil),
            websiteDataStore: .nonPersistent(),
            sheetNavigation: makeTestSheetNavigationManager(scriptSource: ""),
            sheetScale: 100, popupWebView: webView,
            sheetNavigationActions: .init(),
            events: .init(onChange: { _, _, _ in }))
    }
}

@MainActor
private final class StatusWebView: WKWebView {
    var simulatesLoading = false
    override var isLoading: Bool { simulatesLoading }
}
