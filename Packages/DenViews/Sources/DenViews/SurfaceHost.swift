public import AppKit

public func needsFirstResponderActivation(_ firstResponder: NSResponder?, target: NSView) -> Bool {
    guard let firstResponderView = firstResponder as? NSView else { return true }
    return firstResponderView !== target && !firstResponderView.isDescendant(of: target)
}

public final class SurfaceHost<Request: Equatable, Content: NSView>: NSView {
    public let content: Content
    private var request: Request?
    private var onReady: ((NSWindow) -> Bool)?
    private var handledRequest: Request?
    private weak var handledWindow: NSWindow?
    private var isNotificationScheduled = false

    public init(content: Content) {
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

    public required init?(coder: NSCoder) { return nil }

    public func update(request: Request?, onReady: @escaping (NSWindow) -> Bool) {
        if request == nil {
            handledRequest = nil
            handledWindow = nil
        }
        self.request = request
        self.onReady = onReady
        notifyIfReady()
    }

    public override func viewDidMoveToWindow() {
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
