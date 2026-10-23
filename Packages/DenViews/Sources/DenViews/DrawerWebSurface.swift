public import AppKit
public import DenModels
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

    private func update(_ host: SurfaceHost<Bool, NSView>) {
        host.update(request: isFocused ? true : nil) { window in
            guard needsFirstResponderActivation(window.firstResponder, target: webView) else {
                return true
            }
            return window.makeFirstResponder(webView)
        }
    }
}
