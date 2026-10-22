public import AppKit
public import SwiftUI

/// M0's cross-module display probe with externally owned Runtime resources.
public struct NativeSurfaceView: NSViewRepresentable {
    private let surface: NSView

    public init(surface: NSView) {
        self.surface = surface
    }

    public func makeNSView(context: Context) -> NSView {
        surface
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}
}
