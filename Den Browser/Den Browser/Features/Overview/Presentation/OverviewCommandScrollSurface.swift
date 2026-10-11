import AppKit
import SwiftUI

struct OverviewCommandScrollSurface: NSViewRepresentable {
    let onZoom: (CGFloat, CGPoint) -> Bool

    func makeNSView(context: Context) -> CommandScrollView {
        let view = CommandScrollView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ view: CommandScrollView, context: Context) { view.onZoom = onZoom }

    static func dismantleNSView(_ view: CommandScrollView, coordinator: Void) { view.stopMonitoring() }

    final class CommandScrollView: NSView {
        var onZoom: (CGFloat, CGPoint) -> Bool = { _, _ in false }
        private var monitor: Any?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
                    event.modifierFlags.intersection([.command, .shift, .control, .option]) == [.command],
                    event.scrollingDeltaY != 0
                else { return event }
                let anchor = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(anchor) else { return event }
                let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 10)
                return self.onZoom(exp(delta / 200), anchor) ? nil : event
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
