public import AppKit
public import DenModels
public import SwiftUI

public struct WebBoardSurface: NSViewRepresentable {
    let webView: NSView
    let isHidden: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool
    var onBeforeHide: @MainActor () async -> Void = {}

    public init(
        webView: NSView, isHidden: Bool, focusRequest: BoardFocusRequest?, onSurfaceReady: @escaping (NSWindow) -> Bool,
        onBeforeHide: @escaping @MainActor () async -> Void = {}
    ) {
        self.webView = webView
        self.isHidden = isHidden
        self.focusRequest = focusRequest
        self.onSurfaceReady = onSurfaceReady
        self.onBeforeHide = onBeforeHide
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> SurfaceHost<BoardFocusRequest, NSView> {
        context.coordinator.onBeforeHide = onBeforeHide
        let host = SurfaceHost<BoardFocusRequest, NSView>(content: webView)
        webView.isHidden = isHidden
        host.update(request: focusRequest, onReady: onSurfaceReady)
        return host
    }

    public func updateNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, NSView>,
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

    public static func dismantleNSView(_ nsView: SurfaceHost<BoardFocusRequest, NSView>, coordinator: Coordinator) {
        coordinator.hideTask?.cancel()
        coordinator.hideTask = nil
        if !nsView.content.isHidden, let beforeHide = coordinator.onBeforeHide {
            Task { @MainActor in
                await beforeHide()
            }
        }
        coordinator.onBeforeHide = nil
    }

    public final class Coordinator {
        var onBeforeHide: (@MainActor () async -> Void)?
        var hideTask: Task<Void, Never>?
    }
}
