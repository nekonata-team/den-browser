import SwiftUI
import WebKit

struct BoardWebView: NSViewRepresentable {
    let webView: WKWebView
    let isFocused: Bool
    let isPointerFocusEnabled: Bool
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.startRecognizing(webView: webView, onFocus: onFocus)
        context.coordinator.updatePointerFocusEnabled(isPointerFocusEnabled)
        context.coordinator.updateFocus(isFocused, webView: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onFocus = onFocus
        context.coordinator.updatePointerFocusEnabled(isPointerFocusEnabled)
        context.coordinator.updateFocus(isFocused, webView: nsView)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.stopRecognizing()
    }

    final class Coordinator: NSGestureRecognizer {
        private var pointerFocusState = PointerFocusState()
        private var activationWorkItem: DispatchWorkItem?
        fileprivate var onFocus: (() -> Void)?

        init() {
            super.init(target: nil, action: nil)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        deinit {
            activationWorkItem?.cancel()
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
            activationWorkItem?.cancel()
        }

        func updateFocus(_ newValue: Bool, webView: WKWebView) {
            guard newValue != pointerFocusState.isFocused else { return }
            activationWorkItem?.cancel()
            guard pointerFocusState.updateFocus(newValue) else { return }

            guard webView.fullscreenState == .notInFullscreen else { return }

            let workItem = DispatchWorkItem { [weak webView] in
                guard let webView else { return }
                webView.window?.makeFirstResponder(webView)
            }
            activationWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }
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

    mutating func updateFocus(_ newValue: Bool) -> Bool {
        guard newValue != isFocused else { return false }
        isFocused = newValue

        guard newValue else {
            suppressNextActivation = false
            return false
        }

        if suppressNextActivation {
            suppressNextActivation = false
            return false
        }
        return true
    }
}
