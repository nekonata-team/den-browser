import SwiftUI
import WebKit

struct BoardWebView: NSViewRepresentable {
    let webView: WKWebView
    let isFocused: Bool
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.startMonitoring(webView: webView, onFocus: onFocus)
        context.coordinator.updateFocus(isFocused, webView: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onFocus = onFocus
        context.coordinator.updateFocus(isFocused, webView: nsView)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        private var isFocused = false
        private var activationWorkItem: DispatchWorkItem?
        private var mouseMonitor: Any?
        fileprivate var onFocus: (() -> Void)?

        deinit {
            stopMonitoring()
        }

        func startMonitoring(webView: WKWebView, onFocus: @escaping () -> Void) {
            self.onFocus = onFocus
            guard mouseMonitor == nil else { return }

            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak webView] event in
                guard
                    let self,
                    let webView,
                    let contentView = event.window?.contentView,
                    event.window === webView.window,
                    let hitView = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil)),
                    hitView === webView || hitView.isDescendant(of: webView)
                else { return event }

                self.onFocus?()
                return event
            }
        }

        func stopMonitoring() {
            guard let mouseMonitor else { return }
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
            onFocus = nil
            activationWorkItem?.cancel()
        }

        func updateFocus(_ newValue: Bool, webView: WKWebView) {
            guard newValue != isFocused else { return }
            isFocused = newValue
            activationWorkItem?.cancel()

            guard newValue else { return }

            let workItem = DispatchWorkItem { [weak webView] in
                guard let webView else { return }
                webView.window?.makeFirstResponder(webView)
            }
            activationWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
    }
}
