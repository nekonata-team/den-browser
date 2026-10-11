import AppKit
import SwiftUI
import WebKit

struct WebBoardSurface: NSViewRepresentable {
    let webView: WKWebView
    let isHidden: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool
    var onBeforeHide: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SurfaceHost<BoardFocusRequest, WKWebView> {
        context.coordinator.onBeforeHide = onBeforeHide
        let host = SurfaceHost<BoardFocusRequest, WKWebView>(content: webView)
        webView.isHidden = isHidden
        host.update(request: focusRequest, onReady: onSurfaceReady)
        return host
    }

    func updateNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, WKWebView>,
        context: Context
    ) {
        context.coordinator.onBeforeHide = onBeforeHide
        if isHidden && !webView.isHidden { onBeforeHide() }
        webView.isHidden = isHidden
        nsView.update(request: focusRequest, onReady: onSurfaceReady)
    }

    static func dismantleNSView(_ nsView: SurfaceHost<BoardFocusRequest, WKWebView>, coordinator: Coordinator) {
        if !nsView.content.isHidden { coordinator.onBeforeHide?() }
        coordinator.onBeforeHide = nil
    }

    final class Coordinator {
        var onBeforeHide: (() -> Void)?
    }
}
