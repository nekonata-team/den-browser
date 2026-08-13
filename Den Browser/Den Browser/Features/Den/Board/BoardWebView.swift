import SwiftUI
import WebKit

struct BoardFocusRequest: Equatable {
    let deskID: UUID
    let boardID: UUID
}

struct BoardWebView: NSViewRepresentable {
    let webView: WKWebView
    let isFocused: Bool
    let isHidden: Bool
    let isPointerFocusEnabled: Bool
    let focusRequest: BoardFocusRequest?
    let onSurfaceReady: (NSWindow) -> Bool
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SurfaceHost<WKWebView> {
        let host = SurfaceHost(content: webView)
        context.coordinator.startRecognizing(webView: webView, onFocus: onFocus)
        webView.isHidden = isHidden
        context.coordinator.updatePointerFocusEnabled(isPointerFocusEnabled)
        context.coordinator.updateFocus(isFocused)
        host.update(request: focusRequest) { window in
            context.coordinator.handleFocusRequest(in: window, onSurfaceReady: onSurfaceReady)
        }
        return host
    }

    func updateNSView(_ nsView: SurfaceHost<WKWebView>, context: Context) {
        context.coordinator.onFocus = onFocus
        webView.isHidden = isHidden
        context.coordinator.updatePointerFocusEnabled(isPointerFocusEnabled)
        context.coordinator.updateFocus(isFocused)
        nsView.update(request: focusRequest) { window in
            context.coordinator.handleFocusRequest(in: window, onSurfaceReady: onSurfaceReady)
        }
    }

    static func dismantleNSView(_ nsView: SurfaceHost<WKWebView>, coordinator: Coordinator) {
        coordinator.stopRecognizing()
    }

    final class Coordinator: NSGestureRecognizer {
        private var pointerFocusState = PointerFocusState()
        fileprivate var onFocus: (() -> Void)?

        init() {
            super.init(target: nil, action: nil)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        func startRecognizing(webView: WKWebView, onFocus: @escaping () -> Void) {
            self.onFocus = onFocus
            guard view == nil else { return }
            webView.addGestureRecognizer(self)
        }

        override func mouseDown(with event: NSEvent) {
            if pointerFocusState.handlePointerDown() {
                onFocus?()
            }
            state = .failed
        }

        func updatePointerFocusEnabled(_ isEnabled: Bool) {
            pointerFocusState.updateEnabled(isEnabled)
        }

        func stopRecognizing() {
            view?.removeGestureRecognizer(self)
            onFocus = nil
            pointerFocusState.reset()
        }

        func updateFocus(_ newValue: Bool) {
            pointerFocusState.updateFocus(newValue)
        }

        func handleFocusRequest(
            in window: NSWindow,
            onSurfaceReady: (NSWindow) -> Bool
        ) -> Bool {
            guard pointerFocusState.shouldActivateFocusRequest() else { return true }
            return onSurfaceReady(window)
        }
    }
}

func needsFirstResponderActivation(_ firstResponder: NSResponder?, target: NSView) -> Bool {
    guard let firstResponderView = firstResponder as? NSView else { return true }
    return firstResponderView !== target && !firstResponderView.isDescendant(of: target)
}

final class SurfaceHost<Content: NSView>: NSView {
    let content: Content
    private var request: BoardFocusRequest?
    private var onReady: ((NSWindow) -> Bool)?
    private var handledRequest: BoardFocusRequest?
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

    func update(request: BoardFocusRequest?, onReady: @escaping (NSWindow) -> Bool) {
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

struct PointerFocusState {
    private(set) var isEnabled = true
    private(set) var isFocused = false
    private var suppressNextActivation = false

    mutating func updateEnabled(_ newValue: Bool) {
        isEnabled = newValue
        if !newValue {
            suppressNextActivation = false
        }
    }

    mutating func handlePointerDown() -> Bool {
        guard isEnabled else { return false }
        if !isFocused {
            suppressNextActivation = true
        }
        return true
    }

    mutating func updateFocus(_ newValue: Bool) {
        guard newValue != isFocused else { return }
        isFocused = newValue

        if !newValue {
            suppressNextActivation = false
        }
    }

    mutating func shouldActivateFocusRequest() -> Bool {
        if suppressNextActivation {
            suppressNextActivation = false
            return false
        }
        return true
    }

    mutating func reset() {
        isFocused = false
        suppressNextActivation = false
    }
}
