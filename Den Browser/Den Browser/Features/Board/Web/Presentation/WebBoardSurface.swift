import AppKit
import SwiftUI
import WebKit

struct WebBoardSurface: NSViewRepresentable {
    let webView: WKWebView
    let isHidden: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool
    var onBeforeHide: @MainActor () async -> Void = {}

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
        if isHidden {
            if !webView.isHidden, context.coordinator.hideTask == nil {
                let beforeHide = onBeforeHide
                context.coordinator.hideTask = Task {
                    @MainActor [weak coordinator = context.coordinator, weak webView] in
                    defer { coordinator?.hideTask = nil }
                    await beforeHide()
                    guard !Task.isCancelled else { return }
                    webView?.isHidden = true
                }
            }
        } else {
            context.coordinator.hideTask?.cancel()
            context.coordinator.hideTask = nil
            webView.isHidden = false
        }
        nsView.update(request: focusRequest, onReady: onSurfaceReady)
    }

    static func dismantleNSView(_ nsView: SurfaceHost<BoardFocusRequest, WKWebView>, coordinator: Coordinator) {
        coordinator.hideTask?.cancel()
        coordinator.hideTask = nil
        if !nsView.content.isHidden, let beforeHide = coordinator.onBeforeHide {
            Task { @MainActor in
                await beforeHide()
            }
        }
        coordinator.onBeforeHide = nil
    }

    final class Coordinator {
        var onBeforeHide: (@MainActor () async -> Void)?
        var hideTask: Task<Void, Never>?
    }
}
