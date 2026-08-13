import AppKit
import Testing

@testable import Den_Browser

@MainActor
struct PointerFocusStateTests {
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
        let host = SurfaceHost(content: NSView())
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

    @Test func pointerFocusSuppressesExplicitActivation() {
        var state = PointerFocusState()

        let handledPointer = state.handlePointerDown()
        state.updateFocus(true)
        let activatedAfterPointer = state.shouldActivateFocusRequest()
        #expect(handledPointer)
        #expect(!activatedAfterPointer)
        state.updateFocus(false)
        state.updateFocus(true)
        let activatedAfterKeyboardFocus = state.shouldActivateFocusRequest()
        #expect(activatedAfterKeyboardFocus)
    }

    @Test func disabledPointerFocusHasNoCallbackOrSuppression() {
        var state = PointerFocusState()
        _ = state.handlePointerDown()
        state.updateEnabled(false)

        let handledPointer = state.handlePointerDown()
        #expect(!handledPointer)
        state.updateEnabled(true)
        state.updateFocus(true)
        let activated = state.shouldActivateFocusRequest()
        #expect(activated)
    }

    @Test func resetClearsPendingPointerFocus() {
        var state = PointerFocusState()
        _ = state.handlePointerDown()
        state.reset()

        state.updateFocus(true)
        let activated = state.shouldActivateFocusRequest()
        #expect(activated)
    }
}
