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

    static func syncActiveFieldEditor(to value: String) {
        guard
            let textView = (NSApp.keyWindow?.firstResponder as? NSTextView)
                ?? NSApp.windows.compactMap({ $0.firstResponder as? NSTextView }).first,
            !textView.hasMarkedText()
        else { return }

        DispatchQueue.main.async {
            guard
                textView.window?.firstResponder === textView,
                !textView.hasMarkedText(),
                textView.string != value
            else { return }
            textView.string = value
            textView.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
        }
    }
}
