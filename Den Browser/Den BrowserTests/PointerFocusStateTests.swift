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

    @Test func webPointerFocusSuppressesExplicitActivation() {
        var state = PointerFocusState()

        let handledPointer = state.handlePointerDown()
        let activatedAfterPointer = state.updateFocus(true)
        #expect(handledPointer)
        #expect(!activatedAfterPointer)
        _ = state.updateFocus(false)
        let activatedAfterKeyboardFocus = state.updateFocus(true)
        #expect(activatedAfterKeyboardFocus)
    }

    @Test func disabledWebPointerFocusHasNoCallbackOrSuppression() {
        var state = PointerFocusState()
        _ = state.handlePointerDown()
        state.updateEnabled(false)

        let handledPointer = state.handlePointerDown()
        #expect(!handledPointer)
        state.updateEnabled(true)
        let activated = state.updateFocus(true)
        #expect(activated)
    }
}
