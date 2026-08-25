import SwiftUI
import WebKit

struct BoardFocusRequest: Equatable {
    let deskID: UUID
    let boardID: UUID
}

struct BoardWebView: NSViewRepresentable {
    let webView: WKWebView
    let isHidden: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool

    func makeNSView(context _: Context) -> SurfaceHost<BoardFocusRequest, WKWebView> {
        let host = SurfaceHost<BoardFocusRequest, WKWebView>(content: webView)
        webView.isHidden = isHidden
        host.update(request: focusRequest, onReady: onSurfaceReady)
        return host
    }

    func updateNSView(
        _ nsView: SurfaceHost<BoardFocusRequest, WKWebView>,
        context _: Context
    ) {
        webView.isHidden = isHidden
        nsView.update(request: focusRequest, onReady: onSurfaceReady)
    }
}

func needsFirstResponderActivation(_ firstResponder: NSResponder?, target: NSView) -> Bool {
    guard let firstResponderView = firstResponder as? NSView else { return true }
    return firstResponderView !== target && !firstResponderView.isDescendant(of: target)
}

final class SurfaceHost<Request: Equatable, Content: NSView>: NSView {
    let content: Content
    private var request: Request?
    private var onReady: ((NSWindow) -> Bool)?
    private var handledRequest: Request?
    private weak var handledWindow: NSWindow?
    private var isNotificationScheduled = false

    init(content: Content) {
        self.content = content
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { return nil }

    func update(request: Request?, onReady: @escaping (NSWindow) -> Bool) {
        if request == nil {
            handledRequest = nil
            handledWindow = nil
        }
        self.request = request
        self.onReady = onReady
        notifyIfReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            handledWindow = nil
            return
        }
        notifyIfReady()
    }

    private func notifyIfReady() {
        guard request != nil, window != nil, !isNotificationScheduled else { return }
        isNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isNotificationScheduled = false
            self.notifyIfReadyNow()
        }
    }

    private func notifyIfReadyNow() {
        guard let request, let window, let onReady else {
            return
        }
        if request == handledRequest, let handledWindow, handledWindow === window { return }
        guard onReady(window) else { return }
        handledRequest = request
        handledWindow = window
    }
}
