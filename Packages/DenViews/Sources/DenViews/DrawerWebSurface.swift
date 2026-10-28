public import AppKit
public import SwiftUI

public struct DrawerWebSurface: NSViewRepresentable {
    let webView: NSView
    let isFocused: Bool

    public init(webView: NSView, isFocused: Bool) {
        self.webView = webView
        self.isFocused = isFocused
    }

    public func makeNSView(context: Context) -> SurfaceHost<Bool, NSView> {
        let host = SurfaceHost<Bool, NSView>(content: webView)
        update(host)
        return host
    }

    public func updateNSView(_ nsView: SurfaceHost<Bool, NSView>, context: Context) {
        update(nsView)
    }

    public static func dismantleNSView(_ nsView: SurfaceHost<Bool, NSView>, coordinator: Void) {
        // A newer Drawer or Board host may already own the same live WebView.
        guard nsView.content.superview === nsView else { return }
        nsView.content.isHidden = true
        nsView.content.removeFromSuperview()
    }

    private func update(_ host: SurfaceHost<Bool, NSView>) {
        guard webView.superview === host else { return }
        webView.isHidden = false
        host.update(request: isFocused ? true : nil) { [weak host] window in
            guard let host, webView.superview === host else { return false }
            guard needsFirstResponderActivation(window.firstResponder, target: webView) else {
                return true
            }
            return window.makeFirstResponder(webView)
        }
    }
}
