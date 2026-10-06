import SwiftUI
import WebKit

struct DrawerWebSurface: NSViewRepresentable {
    let webView: WKWebView
    let isFocused: Bool

    func makeNSView(context: Context) -> SurfaceHost<Bool, WKWebView> {
        let host = SurfaceHost<Bool, WKWebView>(content: webView)
        update(host)
        return host
    }

    func updateNSView(_ nsView: SurfaceHost<Bool, WKWebView>, context: Context) {
        update(nsView)
    }

    private func update(_ host: SurfaceHost<Bool, WKWebView>) {
        host.update(request: isFocused ? true : nil) { window in
            guard needsFirstResponderActivation(window.firstResponder, target: webView) else {
                return true
            }
            return window.makeFirstResponder(webView)
        }
    }
}
