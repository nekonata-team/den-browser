public import AppKit
public import DenPresentationModels
public import SwiftUI

public struct TerminalBoardSurface: NSViewRepresentable {
    let terminalView: NSView
    let onSurfaceVisibilityChange: (Bool) -> Void
    let onBeforeHide: () -> Void
    let isHidden: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool

    public init(
        terminalView: NSView, onSurfaceVisibilityChange: @escaping (Bool) -> Void, onBeforeHide: @escaping () -> Void,
        isHidden: Bool, focusRequest: BoardFocusRequest?, onSurfaceReady: @escaping (NSWindow) -> Bool
    ) {
        self.terminalView = terminalView
        self.onSurfaceVisibilityChange = onSurfaceVisibilityChange
        self.onBeforeHide = onBeforeHide
        self.isHidden = isHidden
        self.focusRequest = focusRequest
        self.onSurfaceReady = onSurfaceReady
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> SurfaceHost<BoardFocusRequest, NSView> {
        let host = SurfaceHost<BoardFocusRequest, NSView>(content: terminalView)
        update(terminalView, coordinator: context.coordinator)
        host.update(request: focusRequest, onReady: onSurfaceReady)
        return host
    }

    public func updateNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, NSView>,
        context: Context
    ) {
        update(terminalView, coordinator: context.coordinator)
        nsView.update(request: focusRequest, onReady: onSurfaceReady)
    }

    public static func dismantleNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, NSView>,
        coordinator: Coordinator
    ) {
        if !nsView.content.isHidden { coordinator.onBeforeHide?() }
        coordinator.onSurfaceVisibilityChange?(false)
        coordinator.onSurfaceVisibilityChange = nil
        coordinator.onBeforeHide = nil
    }

    private func update(_ view: NSView, coordinator: Coordinator) {
        coordinator.onSurfaceVisibilityChange = onSurfaceVisibilityChange
        coordinator.onBeforeHide = onBeforeHide
        if isHidden && !view.isHidden { onBeforeHide() }
        view.isHidden = isHidden
        onSurfaceVisibilityChange(!isHidden)
    }

    public final class Coordinator {
        fileprivate var onSurfaceVisibilityChange: ((Bool) -> Void)?
        fileprivate var onBeforeHide: (() -> Void)?
    }
}
