import SwiftUI
import WebKit

struct BoardWebView: NSViewRepresentable {
    let webView: WKWebView
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.updateFocus(isFocused, webView: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.updateFocus(isFocused, webView: nsView)
    }

    final class Coordinator {
        private var isFocused = false
        private var activationWorkItem: DispatchWorkItem?

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
