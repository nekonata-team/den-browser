import AppKit
import SwiftUI
import WebKit

struct BoardWebView: NSViewRepresentable {
    let webView: WKWebView
    let isHidden: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool

    func makeNSView(context _: Context) -> SurfaceHost<BoardFocusRequest, WKWebView> {
        let host = SurfaceHost<BoardFocusRequest, WKWebView>(content: webView)
        webView.isHidden = isHidden
        host.update(request: focusRequest, onReady: onSurfaceReady)
        return host
    }

    func updateNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, WKWebView>,
        context _: Context
    ) {
        webView.isHidden = isHidden
        nsView.update(request: focusRequest, onReady: onSurfaceReady)
    }
}
