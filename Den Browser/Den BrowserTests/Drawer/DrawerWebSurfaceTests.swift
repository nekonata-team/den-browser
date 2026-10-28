import AppKit
import DenModels
import DenViews
import SwiftUI
import Testing

@testable import Den_Browser

@MainActor
struct DrawerWebSurfaceTests {
    @Test func mountingRestoresVisibilityAfterClosingDrawer() {
        // Arrange
        let surface = NSView()
        let previousHost = SurfaceHost<Bool, NSView>(content: surface)
        DrawerWebSurface.dismantleNSView(previousHost, coordinator: ())
        let window = TestWindow()
        defer { window.contentView = nil }

        // Act
        window.contentView = NSHostingView(rootView: DrawerWebSurface(webView: surface, isFocused: false))
        window.contentView?.layoutSubtreeIfNeeded()

        // Assert
        #expect(!surface.isHidden)
        #expect(surface.window === window)
    }

    @Test(arguments: [false, true])
    func dismantlingPreviousHostDoesNotHideTransferredSurface(placesAsBoard: Bool) {
        // Arrange
        let surface = NSView()
        let previousHost = SurfaceHost<Bool, NSView>(content: surface)
        let nextHost: NSView =
            if placesAsBoard {
                SurfaceHost<BoardFocusRequest, NSView>(content: surface)
            } else {
                SurfaceHost<Bool, NSView>(content: surface)
            }

        // Act
        DrawerWebSurface.dismantleNSView(previousHost, coordinator: ())

        // Assert
        #expect(!surface.isHidden)
        #expect(surface.superview === nextHost)
    }

    @Test func removingDrawerFromSwiftUITreeHidesTheRetainedSurface() async throws {
        // Arrange
        let surface = NSView()
        let window = TestWindow()
        defer { window.contentView = nil }
        let hosting = NSHostingView(rootView: AnyView(DrawerWebSurface(webView: surface, isFocused: false)))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try #require(surface.window === window)

        // Act
        hosting.rootView = AnyView(EmptyView())
        hosting.layoutSubtreeIfNeeded()
        let deadline = ContinuousClock.now + .seconds(1)
        while !surface.isHidden, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Assert
        #expect(surface.isHidden)
        #expect(surface.superview == nil)
        #expect(surface.window == nil)
    }
}
