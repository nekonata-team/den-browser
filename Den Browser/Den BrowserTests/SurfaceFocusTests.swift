import AppKit
import Testing
import WebKit

@testable import Den_Browser

@MainActor
struct SurfaceFocusTests {
    @Test func firstResponderInsideTargetDoesNotNeedActivation() {
        let target = NSView()
        let child = NSView()
        target.addSubview(child)

        #expect(!needsFirstResponderActivation(target, target: target))
        #expect(!needsFirstResponderActivation(child, target: target))
    }

    @Test func firstResponderOutsideTargetNeedsActivation() {
        let target = NSView()
        let other = NSView()

        #expect(needsFirstResponderActivation(other, target: target))
        #expect(needsFirstResponderActivation(nil, target: target))
    }

    @Test func reattachingSurfaceHandlesSameRequestAgain() async {
        func waitForMainQueue() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let host = SurfaceHost<BoardFocusRequest, NSView>(content: NSView())
        let request = BoardFocusRequest(deskID: UUID(), boardID: UUID())
        var handlingCount = 0
        host.update(request: request) { _ in
            handlingCount += 1
            return true
        }

        window.contentView?.addSubview(host)
        #expect(handlingCount == 0)
        await waitForMainQueue()
        #expect(handlingCount == 1)
        host.removeFromSuperview()
        window.contentView?.addSubview(host)
        await waitForMainQueue()
        #expect(handlingCount == 2)
    }

    @Test func boardWKWebViewBlocksAutofocusWhenUnfocused() {
        let webView = BoardWKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var isFocused = false
        var rejectedCount = 0
        webView.isFocusAllowed = { isFocused }
        webView.onRejectedFocus = { rejectedCount += 1 }

        #expect(!webView.becomeFirstResponder())
        #expect(rejectedCount == 1)

        isFocused = true
        _ = webView.becomeFirstResponder()
        #expect(rejectedCount == 1)
    }

    @Test func boardWKWebViewNotifiesUserInteractionOnMouseDown() {
        let webView = BoardWKWebView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            configuration: WKWebViewConfiguration())
        var interactionCount = 0
        webView.onUserInteraction = { interactionCount += 1 }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        webView.mouseDown(with: event)
        #expect(interactionCount == 1)

        webView.rightMouseDown(with: event)
        #expect(interactionCount == 2)

        webView.otherMouseDown(with: event)
        #expect(interactionCount == 3)
    }
}
