import AppKit
import Testing

@testable import Den_Browser

@MainActor
struct OverviewCanvasInputTests {
    @Test(arguments: [false, true])
    func rightClickPassesThroughAndRightDragPans(drag: Bool) throws {
        // Arrange
        let window = CanvasTestWindow(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [], backing: .buffered, defer: false)
        let view = OverviewCanvasInputSurface.CanvasInputView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView?.addSubview(view)
        defer { view.removeFromSuperview() }
        var translations: [CGSize?] = []
        view.onPan = {
            translations.append($0)
            return true
        }
        let down = try mouse(.rightMouseDown, point: CGPoint(x: 50, y: 50), window: window)
        let move = try mouse(.rightMouseDragged, point: CGPoint(x: 80, y: 70), window: window)
        let mouseUp = try mouse(.rightMouseUp, point: CGPoint(x: 80, y: 70), window: window)

        // Act
        let downResult = view.handle(down)
        let moveResult = drag ? view.handle(move) : move
        let upResult = view.handle(mouseUp)

        // Assert
        #expect(downResult === down)
        if drag {
            #expect(moveResult == nil)
            #expect(upResult == nil)
            #expect(translations == [CGSize(width: 30, height: -20), nil])
        } else {
            #expect(upResult === mouseUp)
            #expect(translations.isEmpty)
        }
    }

    private func mouse(_ type: NSEvent.EventType, point: CGPoint, window: NSWindow) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
}

@MainActor
private final class CanvasTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
