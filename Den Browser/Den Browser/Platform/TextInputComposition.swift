import AppKit

@MainActor
enum TextInputComposition {
    static var isActive: Bool {
        isActive(in: NSApp.keyWindow)
    }

    static func isActive(in window: NSWindow?) -> Bool {
        (window?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    static func performUnlessActive(
        in window: NSWindow? = NSApp.keyWindow,
        _ action: () -> Void
    ) {
        guard !isActive(in: window) else { return }
        action()
    }
}
