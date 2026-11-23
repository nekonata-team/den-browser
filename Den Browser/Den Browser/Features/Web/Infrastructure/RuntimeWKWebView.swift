import AppKit
import WebKit

final class RuntimeWKWebView: WKWebView {
    var isFocusAllowed: () -> Bool = { false }
    var onRejectedFocus: (() -> Void)?
    private(set) var backgroundExecutionEnabled = false
    private(set) var temporaryBackgroundExecutionEnabled = false
    var isEffectiveBackgroundExecutionEnabled: Bool {
        backgroundExecutionEnabled || temporaryBackgroundExecutionEnabled
    }
    private var backgroundWindow: WebBackgroundWindow?
    private var previousOcclusionDetection = true

    // WebKit uses this query independently of NSView's actual drawing visibility.
    override var isHiddenOrHasHiddenAncestor: Bool {
        isEffectiveBackgroundExecutionEnabled ? false : super.isHiddenOrHasHiddenAncestor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !super.isHiddenOrHasHiddenAncestor else { return nil }
        return super.hitTest(point)
    }

    override func becomeFirstResponder() -> Bool {
        guard isFocusAllowed(), !(window is WebBackgroundWindow) else {
            onRejectedFocus?()
            return false
        }
        return super.becomeFirstResponder()
    }

    func setBackgroundExecutionEnabled(_ enabled: Bool) {
        guard enabled != backgroundExecutionEnabled else { return }
        let wasActive = isEffectiveBackgroundExecutionEnabled
        backgroundExecutionEnabled = enabled
        updateBackgroundHosting(wasActive: wasActive)
    }

    func setTemporaryBackgroundExecutionEnabled(_ enabled: Bool) {
        guard enabled != temporaryBackgroundExecutionEnabled else { return }
        let wasActive = isEffectiveBackgroundExecutionEnabled
        temporaryBackgroundExecutionEnabled = enabled
        updateBackgroundHosting(wasActive: wasActive)
    }

    private func updateBackgroundHosting(wasActive: Bool) {
        let isActive = isEffectiveBackgroundExecutionEnabled
        guard isActive != wasActive else { return }
        if isActive {
            previousOcclusionDetection = _windowOcclusionDetectionEnabled
            _windowOcclusionDetectionEnabled = false
            hostInBackgroundIfDetached()
        } else {
            _windowOcclusionDetectionEnabled = previousOcclusionDetection
            if window === backgroundWindow { removeFromSuperview() }
            backgroundWindow?.close()
            backgroundWindow = nil
        }
        // Recompute WebKit's activity state even if NSView's hidden flag did not change.
        super.viewDidUnhide()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard isEffectiveBackgroundExecutionEnabled, window == nil else { return }
        // A new SurfaceHost may be taking ownership during the same run loop.
        Task { @MainActor [weak self] in
            self?.hostInBackgroundIfDetached()
        }
    }

    private func hostInBackgroundIfDetached() {
        guard isEffectiveBackgroundExecutionEnabled, window == nil else { return }
        if backgroundWindow == nil {
            let size = NSSize(
                width: frame.width > 0 ? frame.width : 800,
                height: frame.height > 0 ? frame.height : 600
            )
            let host = WebBackgroundWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            host.isReleasedWhenClosed = false
            host.isExcludedFromWindowsMenu = true
            backgroundWindow = host
        }
        translatesAutoresizingMaskIntoConstraints = true
        if frame.width > 0, frame.height > 0 { backgroundWindow?.setContentSize(frame.size) }
        frame.origin = .zero
        backgroundWindow?.contentView?.addSubview(self)
    }
}

// Never ordered on screen. WebKit still needs a visible window to run animation frames.
private final class WebBackgroundWindow: NSWindow {
    override var isVisible: Bool { true }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
