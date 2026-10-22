import AppKit
import SwiftUI

struct OverviewCanvasInputSurface: NSViewRepresentable {
    let onZoom: (CGFloat, CGPoint) -> Bool
    let onPan: (CGSize?) -> Bool

    func makeNSView(context: Context) -> CanvasInputView {
        let view = CanvasInputView()
        view.onZoom = onZoom
        view.onPan = onPan
        return view
    }

    func updateNSView(_ view: CanvasInputView, context: Context) {
        view.onZoom = onZoom
        view.onPan = onPan
    }

    static func dismantleNSView(_ view: CanvasInputView, coordinator: Void) { view.stopMonitoring() }

    final class CanvasInputView: NSView {
        var onZoom: (CGFloat, CGPoint) -> Bool = { _, _ in false }
        var onPan: (CGSize?) -> Bool = { _ in false }
        private var monitor: Any?
        private var resignObserver: NSObjectProtocol?
        private var panOrigin: CGPoint?
        private var didPan = false

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard let window else { return }
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.endPan() }
            }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .rightMouseDown, .rightMouseDragged, .rightMouseUp]
            ) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func handle(_ event: NSEvent) -> NSEvent? {
            guard event.window === window, window?.isKeyWindow == true, !isHiddenOrHasHiddenAncestor else {
                endPan()
                return event
            }
            let point = convert(event.locationInWindow, from: nil)
            switch event.type {
            case .rightMouseDown:
                endPan()
                if bounds.contains(point) { panOrigin = point }
            case .rightMouseDragged:
                guard let origin = panOrigin else { return event }
                let translation = CGSize(width: point.x - origin.x, height: point.y - origin.y)
                if !didPan && hypot(translation.width, translation.height) < 3 { return event }
                guard onPan(translation) else {
                    endPan()
                    return event
                }
                if !didPan { NSCursor.closedHand.push() }
                didPan = true
                return nil
            case .rightMouseUp:
                let consumed = didPan
                endPan()
                return consumed ? nil : event
            case .scrollWheel:
                guard bounds.contains(point),
                    event.modifierFlags.intersection([.command, .shift, .control, .option]) == [.command],
                    event.scrollingDeltaY != 0
                else { return event }
                let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
                return onZoom(exp(delta / 200), point) ? nil : event
            default:
                break
            }
            return event
        }

        private func endPan() {
            if didPan {
                NSCursor.pop()
                _ = onPan(nil)
            }
            didPan = false
            panOrigin = nil
        }

        func stopMonitoring() {
            endPan()
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            resignObserver = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
