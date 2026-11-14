import AppKit
import DenApplication
import DenDomain
import DenModels
import Foundation
import Testing
import WebKit

@testable import Den_Browser

@MainActor
final class WebViewLoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func load(_ html: String, baseURL: URL, in webView: WKWebView) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        resume()
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }
}

func makeSheetNavigationScriptSource() throws -> String {
    let url = try #require(Bundle.main.url(forResource: "SheetNavigation", withExtension: "js"))
    return try String(contentsOf: url, encoding: .utf8)
}

@MainActor
func makeSheetNavigationWebView(manager: SheetNavigationManager) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController = manager.userContentController
    return WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
}

@MainActor
func makeNoOpSheetNavigationActions() -> SheetNavigationManager.Actions {
    .init(
        onOpenBoard: { _ in },
        onOpenBoardInBackground: { _ in },
        onKeepInDrawer: { _ in },
        onEditCurrentSheet: {},
        onOpenCurrentSheetInNewBoard: { _ in },
        onPasteURLInNewBoard: { _ in },
        onCopyURLSucceeded: {},
        onCopyURLFailed: {},
        onCopyMarkdownLinkSucceeded: {},
        onCopyMarkdownLinkFailed: {},
        onPasteURLFailed: {},
        onOpenBoardPanel: {},
        onShowOverview: {},
        onShowEssentials: {},
        onRemoveBoard: {},
        onRemoveBoardAndFocusNext: {},
        onRestoreBoard: {},
        onFocusFirstBoard: {},
        onFocusLastBoard: {},
        onFocusPreviousBoard: {},
        onFocusNextBoard: {},
        onGoToFirstSheet: {},
        onGoToLatestSheet: {},
        isSupportedSheetURL: WebURLPolicy.isSupported,
        onNavigateCurrentSheet: { _ in }
    )
}

@MainActor
func boardRuntimeEvents(
    onChange: @escaping (BoardID, URL?, String?) -> Void = { _, _, _ in },
    onFullscreenChange: ((BoardID, Bool) -> Void)? = nil,
    onDownloadFinished: @escaping (String) -> Void = { _ in },
    onDownloadFailed: @escaping (String) -> Void = { _ in }
) -> WebRuntime.Events {
    .init(
        onChange: onChange,
        onFullscreenChange: onFullscreenChange,
        onDownloadFinished: onDownloadFinished,
        onDownloadFailed: onDownloadFailed
    )
}

@MainActor
@discardableResult
func dispatchSheetKey(
    _ key: String,
    shift: Bool = false,
    in webView: WKWebView
) async throws -> Bool {
    let keyData = try JSONEncoder().encode(key)
    guard let keyLiteral = String(data: keyData, encoding: .utf8) else { return false }
    let wasPrevented =
        try await webView.evaluateJavaScript(
            "(() => { const event = new KeyboardEvent('keydown', "
                + "{key: \(keyLiteral), shiftKey: \(shift), bubbles: true, cancelable: true}); "
                + "document.dispatchEvent(event); return event.defaultPrevented; })()"
        ) as? Bool
    return wasPrevented ?? false
}

let sheetNavigationTestHTML = """
    <!doctype html>
    <style>
      html, body { margin: 0; width: 2400px; height: 4000px; }
    </style>
    <a href="https://destination.example/">Destination</a>
    <p>find target</p>
    """

let editableControlsTestHTML = """
    <!doctype html>
    <style>
      body { margin: 0; height: 4000px; }
      #composer { margin-top: 3800px; }
    </style>
    <input id="first-text" type="text">
    <input id="hidden-input" type="text" hidden>
    <input id="disabled-input" type="text" disabled>
    <input id="readonly-input" type="text" readonly>
    <input id="file-input" type="file">
    <textarea id="message"></textarea>
    <div id="composer" contenteditable="true" role="textbox"></div>
    """
